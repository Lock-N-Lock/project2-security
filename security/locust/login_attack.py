# security/locust/login_attack.py
# GET /login으로 CSRF(쿠키+히든필드) 획득 후 form+틀린비번 POST → 401 유발
import re
from locust import HttpUser, task, constant


class LoginAttackUser(HttpUser):
    wait_time = constant(0)

    @task
    def brute_force_login(self):
        # 1) CSRF 토큰 확보 (쿠키 우선, 실패 시 히든필드 — 속성 순서 양방향 대응)
        r = self.client.get("/login", name="GET /login")
        token = self.client.cookies.get("csrf_token")
        if not token:
            m = re.search(
                r'name="csrf_token"\s+value="([^"]+)"'
                r'|value="([^"]+)"\s+name="csrf_token"',
                r.text,
            )
            token = (m.group(1) or m.group(2)) if m else ""

        # 토큰을 못 얻으면 422/403 노이즈만 나니 보내지 않음
        if not token:
            return

        # 2) form-encoded + 틀린 비번 + csrf → 핸들러 도달 → 401
        self.client.post(
            "/login",
            name="POST /login (attack)",
            data={"username": "user1", "password": "wrong-password", "csrf_token": token},
            headers={"User-Agent": "Locust-Login-Attack"},
        )
