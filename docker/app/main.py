import os
import logging
import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, Request, Form, Response, Cookie, Depends
from fastapi.responses import HTMLResponse, RedirectResponse, PlainTextResponse
from fastapi.templating import Jinja2Templates
import bcrypt
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
import socket
import urllib.request

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_server_info():
    try:
        req = urllib.request.Request("http://169.254.169.254/latest/api/token", method="PUT")
        req.add_header("X-aws-ec2-metadata-token-ttl-seconds", "21600")
        with urllib.request.urlopen(req, timeout=1) as response:
            token = response.read().decode('utf-8')
            
        req2 = urllib.request.Request("http://169.254.169.254/latest/meta-data/local-ipv4")
        req2.add_header("X-aws-ec2-metadata-token", token)
        with urllib.request.urlopen(req2, timeout=1) as response:
            ip = response.read().decode('utf-8')
            return f"IP: {ip}"
    except:
        return f"Host: {socket.gethostname()}"

SERVER_INFO = get_server_info()

login_failed_total = Counter("login_failed_total", "Total failed login attempts")
transfer_requests_total = Counter("transfer_requests_total", "Total transfer requests")

app = FastAPI()

templates = Jinja2Templates(directory="templates")
templates.env.globals['server_info'] = SERVER_INFO

# Database configurations from environment variables
DB_HOST_MAIN = os.getenv("DB_HOST_MAIN", "127.0.0.1")
DB_HOST_REPLICA = os.getenv("DB_HOST_REPLICA", "127.0.0.1")
DB_USER = os.getenv("DB_USER", "lb-user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "lb-user")
DB_NAME = os.getenv("DB_NAME", "lb-db")

def get_db_connection(host: str):
    return psycopg2.connect(
        host=host,
        user=DB_USER,
        password=DB_PASSWORD,
        dbname=DB_NAME
    )

def get_current_user(request: Request):
    user_id = request.cookies.get("session_token")
    if not user_id:
        return None
    return int(user_id)

@app.get("/", response_class=HTMLResponse)
def read_root(request: Request):
    if get_current_user(request):
        return RedirectResponse(url="/dashboard", status_code=302)
    return RedirectResponse(url="/login", status_code=302)

@app.get("/login", response_class=HTMLResponse)
def login_page(request: Request, error: str = None):
    return templates.TemplateResponse(request, "login.html", {"request": request, "error": error})

@app.post("/login")
def login(request: Request, response: Response, username: str = Form(...), password: str = Form(...)):
    try:
        # READ from Replica
        conn = get_db_connection(DB_HOST_REPLICA)
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("SELECT id, username, password FROM users WHERE username = %s", (username,))
        user = cur.fetchone()
        cur.close()
        conn.close()

        if not user or not bcrypt.checkpw(password.encode('utf-8'), user['password'].encode('utf-8')):
            client_ip = request.client.host
            logger.warning(f"[SECURITY] LOGIN_FAILURE - IP: {client_ip}, Username: {username}")
            login_failed_total.inc()
            return RedirectResponse(url="/login?error=Invalid username or password", status_code=302)
        
        # Simple session using cookie
        redirect = RedirectResponse(url="/dashboard", status_code=302)
        redirect.set_cookie(key="session_token", value=str(user['id']), httponly=True)
        return redirect

    except Exception as e:
        return RedirectResponse(url=f"/login?error={str(e)}", status_code=302)

@app.get("/logout")
def logout():
    redirect = RedirectResponse(url="/login", status_code=302)
    redirect.delete_cookie("session_token")
    return redirect

@app.get("/dashboard", response_class=HTMLResponse)
def dashboard(request: Request):
    user_id = get_current_user(request)
    if not user_id:
        return RedirectResponse(url="/login", status_code=302)
    
    try:
        # READ from Replica
        conn = get_db_connection(DB_HOST_REPLICA)
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        cur.execute("SELECT username, balance FROM users WHERE id = %s", (user_id,))
        user = cur.fetchone()
        
        cur.execute("""
            SELECT title, amount 
            FROM transactions 
            WHERE user_id = %s 
            ORDER BY created_at DESC 
            LIMIT 5
        """, (user_id,))
        transactions = cur.fetchall()
        
        cur.close()
        conn.close()
        
        return templates.TemplateResponse(request, "dashboard.html", {
            "request": request, 
            "username": user['username'], 
            "balance": f"{user['balance']:,}",
            "transactions": transactions
        })
    except Exception as e:
        return RedirectResponse(url=f"/login?error=Dashboard Error: {str(e)}", status_code=302)

@app.get("/transfer", response_class=HTMLResponse)
def transfer_page(request: Request, message: str = None, error: str = None):
    user_id = get_current_user(request)
    if not user_id:
        return RedirectResponse(url="/login", status_code=302)
    return templates.TemplateResponse(request, "transfer.html", {"request": request, "message": message, "error": error})

@app.post("/transfer")
def process_transfer(request: Request, account: str = Form(...), amount: int = Form(...)):
    transfer_requests_total.inc()
    user_id = get_current_user(request)
    if not user_id:
        return RedirectResponse(url="/login", status_code=302)
    
    if amount <= 0:
        return RedirectResponse(url="/transfer?error=Invalid amount", status_code=302)

    conn = None
    try:
        # WRITE to Main DB
        conn = get_db_connection(DB_HOST_MAIN)
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        cur.execute("BEGIN;")
        
        # Check sender balance
        cur.execute("SELECT balance, account_number FROM users WHERE id = %s FOR UPDATE", (user_id,))
        sender = cur.fetchone()
        
        if not sender or sender['balance'] < amount:
            cur.execute("ROLLBACK;")
            cur.close()
            conn.close()
            return RedirectResponse(url="/transfer?error=Insufficient funds", status_code=302)
            
        # Check receiver
        cur.execute("SELECT id FROM users WHERE account_number = %s FOR UPDATE", (account,))
        receiver = cur.fetchone()
        
        if not receiver:
            cur.execute("ROLLBACK;")
            cur.close()
            conn.close()
            return RedirectResponse(url="/transfer?error=Receiver not found", status_code=302)
            
        # Deduct from sender
        cur.execute("UPDATE users SET balance = balance - %s WHERE id = %s", (amount, user_id))
        
        # Add to receiver
        cur.execute("UPDATE users SET balance = balance + %s WHERE id = %s", (amount, receiver['id']))
        
        # Insert transaction record for sender
        cur.execute("""
            INSERT INTO transactions (user_id, target_account, title, amount) 
            VALUES (%s, %s, %s, %s)
        """, (user_id, account, '송금', -amount))
        
        # Add positive record for receiver
        cur.execute("""
            INSERT INTO transactions (user_id, target_account, title, amount) 
            VALUES (%s, %s, %s, %s)
        """, (receiver['id'], sender['account_number'], '입금', amount))
        
        conn.commit()
        cur.close()
        conn.close()
        
        return RedirectResponse(url="/dashboard", status_code=302)
        
    except Exception as e:
        if conn:
            conn.rollback()
            conn.close()
        return RedirectResponse(url=f"/transfer?error=Transfer failed: {str(e)}", status_code=302)

@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)