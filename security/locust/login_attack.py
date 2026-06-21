# security/locust/login_attack.py
# 로그인 브루트포스: GET /login 으로 CSRF(쿠키+히든필드) 획득 후
# form-encoded + 틀린 비번으로 POST → 401 유발 (fail2ban·nginx_login_401_count 점등)

import re
from locust import HttpUser, task, constant


class LoginAttackUser(HttpUser):
    wait_time = constant(0)

    @task
    def brute_force_login(self):
        # 1) 로그인 페이지에서 CSRF 토큰 확보 (쿠키 우선, 실패 시 히든필드 파싱)
        r = self.client.get("/login", name="GET /login")
        token = self.client.cookies.get("csrf_token")
        if not token:
            m = re.search(r'name="csrf_token"\s+value="([^"]+)"', r.text)
            token = m.group(1) if m else ""

        # 2) form-encoded + 틀린 비번 + csrf → 핸들러 도달 → 401
        self.client.post(
            "/login",
            name="POST /login (attack)",
            data={
                "username": "user1",
                "password": "wrong-password",
                "csrf_token": token,
            },
            headers={"User-Agent": "Locust-Login-Attack"},
        )
