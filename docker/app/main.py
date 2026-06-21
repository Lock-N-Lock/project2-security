import os
import secrets
import logging
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import ThreadedConnectionPool
from fastapi import FastAPI, Request, Form, Response, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
import bcrypt
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
import socket
import urllib.request
from contextlib import contextmanager, asynccontextmanager
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
# import requests # 👈 urllib 대신 깔끔한 requests 라이브러리 임포트

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_server_info():
    try:
        req = urllib.request.Request("http://169.254.169.254/latest/api/token", method="PUT")
        req.add_header("X-aws-ec2-metadata-token-ttl-seconds", "21600")
        with urllib.request.urlopen(req, timeout=1) as response:  # nosec
            token = response.read().decode('utf-8')
            
        req2 = urllib.request.Request("http://169.254.169.254/latest/meta-data/local-ipv4")
        req2.add_header("X-aws-ec2-metadata-token", token)
        with urllib.request.urlopen(req2, timeout=1) as response:  # nosec
            ip = response.read().decode('utf-8')
            return f"IP: {ip}"
    except:
        return f"Host: {socket.gethostname()}"
# Bandit: requests 라이브러리로 교체
# def get_server_info():
#     try:
#         # 1. IMDSv2 토큰 가져오기 (PUT 메서드)
#         headers = {"X-aws-ec2-metadata-token-ttl-seconds": "21600"}
#         response = requests.put("http://169.254.169.254/latest/api/token", headers=headers, timeout=1)
#         token = response.text

#         # 2. 발급받은 토큰으로 메타데이터(EC2 내부 IP) 조회 (GET 메서드)
#         headers2 = {"X-aws-ec2-metadata-token": token}
#         response2 = requests.get("http://169.254.169.254/latest/meta-data/local-ipv4", headers=headers2, timeout=1)
#         ip = response2.text
        
#         return f"IP: {ip}"
        
#     except Exception:
#         # AWS 환경이 아니거나 메타데이터 조회가 실패하면 (로컬 PC나 빌드 환경 등)
#         return f"Host: {socket.gethostname()}"
SERVER_INFO = get_server_info()

login_failed_total = Counter("login_failed_total", "Total failed login attempts")
transfer_requests_total = Counter("transfer_requests_total", "Total transfer requests")

# Database configurations from environment variables
DB_HOST_MAIN = os.getenv("DB_HOST_MAIN", "127.0.0.1")
DB_HOST_REPLICA = os.getenv("DB_HOST_REPLICA", "127.0.0.1")
DB_USER = os.getenv("DB_USER", "lb-user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "lb-user")
DB_NAME = os.getenv("DB_NAME", "lb-db")

# Session signing secret key
SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-production")
SESSION_MAX_AGE = 86400  # 24 hours
session_serializer = URLSafeTimedSerializer(SECRET_KEY)

# Dummy bcrypt hash to prevent username enumeration via timing attack
DUMMY_HASH = bcrypt.hashpw(b"dummy", bcrypt.gensalt()).decode('utf-8')

# Connection pool globals
main_pool = None
replica_pool = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global main_pool, replica_pool
    main_pool = ThreadedConnectionPool(
        1, 10,
        host=DB_HOST_MAIN, user=DB_USER, password=DB_PASSWORD, dbname=DB_NAME
    )
    replica_pool = ThreadedConnectionPool(
        1, 10,
        host=DB_HOST_REPLICA, user=DB_USER, password=DB_PASSWORD, dbname=DB_NAME
    )
    logger.info("Database connection pools initialized (main: %s, replica: %s)", DB_HOST_MAIN, DB_HOST_REPLICA)
    yield
    main_pool.closeall()
    replica_pool.closeall()
    logger.info("Database connection pools closed")

app = FastAPI(lifespan=lifespan)

templates = Jinja2Templates(directory="templates")
templates.env.globals['server_info'] = SERVER_INFO

class TransferError(Exception):
    def __init__(self, message: str, status_code: int):
        self.message = message
        self.status_code = status_code

def render_login(request: Request, error: str, status_code: int):
    csrf_token = generate_csrf_token()
    response = templates.TemplateResponse(
        request,
        "login.html",
        {"request": request, "error": error, "csrf_token": csrf_token},
        status_code=status_code,
    )
    response.set_cookie(key="csrf_token", value=csrf_token, httponly=True, secure=True, samesite="lax")
    return response

def render_transfer(request: Request, error: str, status_code: int, message: str = None):
    csrf_token = generate_csrf_token()
    response = templates.TemplateResponse(
        request,
        "transfer.html",
        {"request": request, "message": message, "error": error, "csrf_token": csrf_token},
        status_code=status_code,
    )
    response.set_cookie(key="csrf_token", value=csrf_token, httponly=True, secure=True, samesite="lax")
    return response


@contextmanager
def get_db_connection(pool):
    conn = pool.getconn()
    try:
        yield conn
    except Exception:
        conn.rollback()
        raise
    finally:
        try:
            conn.rollback()
        except Exception:
            pass
        pool.putconn(conn)

def get_current_user(request: Request):
    token = request.cookies.get("session_token")
    if not token:
        return None
    try:
        user_id = session_serializer.loads(token, max_age=SESSION_MAX_AGE)
        return int(user_id)
    except (BadSignature, SignatureExpired):
        return None

def generate_csrf_token():
    return secrets.token_urlsafe(32)

def validate_csrf_token(request: Request, csrf_token_form: str) -> bool:
    csrf_token_cookie = request.cookies.get("csrf_token")
    if not csrf_token_cookie or not csrf_token_form:
        return False
    return secrets.compare_digest(csrf_token_cookie, csrf_token_form)

@app.get("/", response_class=HTMLResponse)
def read_root(request: Request):
    if get_current_user(request):
        return RedirectResponse(url="/dashboard", status_code=302)
    return RedirectResponse(url="/login", status_code=302)

@app.get("/login", response_class=HTMLResponse)
def login_page(request: Request, error: str = None):
    return render_login(request, error, status.HTTP_200_OK)

@app.post("/login")
def login(request: Request, response: Response, username: str = Form(...), password: str = Form(...), csrf_token: str = Form(...)):
    if not validate_csrf_token(request, csrf_token):
        logger.warning("[SECURITY] CSRF_FAILURE - Path: /login, IP: %s", request.client.host)
        return render_login(request, "Invalid request", status.HTTP_403_FORBIDDEN)
    try:
        # READ from Replica
        with get_db_connection(replica_pool) as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT id, username, password FROM users WHERE username = %s", (username,))
                user = cur.fetchone()

        # Always run bcrypt.checkpw to prevent timing-based username enumeration
        stored_hash = user['password'] if user else DUMMY_HASH
        password_valid = bcrypt.checkpw(password.encode('utf-8'), stored_hash.encode('utf-8'))

        if not user or not password_valid:
            client_ip = request.client.host
            logger.warning(f"[SECURITY] LOGIN_FAILURE - IP: {client_ip}, Username: {username}")
            login_failed_total.inc()
            return render_login(request, "Invalid username or password", status.HTTP_401_UNAUTHORIZED)
        
        # Simple session using cookie
        signed_token = session_serializer.dumps(user['id'])
        redirect = RedirectResponse(url="/dashboard", status_code=302)
        redirect.set_cookie(key="session_token", value=signed_token, httponly=True, secure=True, samesite="lax")
        return redirect

    except Exception as e:
        logger.error(f"[SYSTEM ERROR] Login process failure: {str(e)}")
        return render_login(request, "Internal Server Error. Please try again later.", status.HTTP_500_INTERNAL_SERVER_ERROR)

@app.get("/logout")
def logout():
    redirect = RedirectResponse(url="/login", status_code=302)
    redirect.delete_cookie("session_token")
    return redirect

@app.get("/dashboard", response_class=HTMLResponse)
def dashboard(request: Request):
    user_id = get_current_user(request)
    if not user_id:
        return render_login(request, "Login required", status.HTTP_401_UNAUTHORIZED)
    
    try:
        # READ from Replica
        with get_db_connection(replica_pool) as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
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
        
        return templates.TemplateResponse(request, "dashboard.html", {
            "request": request, 
            "username": user['username'], 
            "balance": f"{user['balance']:,}",
            "transactions": transactions
        })
    except Exception as e:
        logger.error("[SYSTEM ERROR] Dashboard failure: %s", str(e))
        return render_login(request, "Dashboard Error. Please try again later.", status.HTTP_500_INTERNAL_SERVER_ERROR)

@app.get("/transfer", response_class=HTMLResponse)
def transfer_page(request: Request, message: str = None, error: str = None):
    user_id = get_current_user(request)
    if not user_id:
        return render_login(request, "Login required", status.HTTP_401_UNAUTHORIZED)
    return render_transfer(request, error, status.HTTP_200_OK, message)

@app.post("/transfer")
def process_transfer(request: Request, account: str = Form(...), amount: int = Form(...), csrf_token: str = Form(...)):
    if not validate_csrf_token(request, csrf_token):
        logger.warning("[SECURITY] CSRF_FAILURE - Path: /transfer, IP: %s", request.client.host)
        return render_transfer(request, "Invalid request", status.HTTP_403_FORBIDDEN)
    transfer_requests_total.inc()
    user_id = get_current_user(request)
    if not user_id:
        return render_login(request, "Login required", status.HTTP_401_UNAUTHORIZED)
    
    if amount <= 0:
        return render_transfer(request, "Invalid amount", status.HTTP_400_BAD_REQUEST)

    try:
        # WRITE to Main DB
        with get_db_connection(main_pool) as conn:
            with conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    # First, look up receiver ID without locking
                    cur.execute("SELECT id FROM users WHERE account_number = %s", (account,))
                    receiver = cur.fetchone()
                    
                    if not receiver:
                        raise TransferError("Receiver not found", status.HTTP_404_NOT_FOUND)

                    if user_id == receiver['id']:
                        raise TransferError("Cannot transfer to yourself", status.HTTP_400_BAD_REQUEST)
                    
                    # Lock rows in consistent ascending ID order to prevent deadlock
                    first_id, second_id = sorted([user_id, receiver['id']])
                    cur.execute("SELECT id, balance, account_number FROM users WHERE id IN (%s, %s) ORDER BY id FOR UPDATE", (first_id, second_id))
                    locked_users = {row['id']: row for row in cur.fetchall()}
                    
                    sender = locked_users.get(user_id)
                    
                    if not sender or sender['balance'] < amount:
                        raise TransferError("Insufficient funds", status.HTTP_400_BAD_REQUEST)
                        
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
            
            return RedirectResponse(url="/dashboard", status_code=302)

    except TransferError as e:
        return render_transfer(request, e.message, e.status_code)
    except Exception as e:
        logger.error("[SYSTEM ERROR] Transfer process failure: %s", str(e))
        return render_transfer(request, "Transfer failed. Please try again later.", status.HTTP_500_INTERNAL_SERVER_ERROR)

@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
