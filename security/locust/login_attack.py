# security/locust/login_attack.py
import re
from locust import HttpUser, task, constant


class LoginAttackUser(HttpUser):
    wait_time = constant(1)

    @task
    def brute_force_login(self):
        headers = {"User-Agent": "Locust-Login-Attack"}

        r = self.client.get(
            "/login",
            name="GET /login",
            headers=headers,
        )

        token = self.client.cookies.get("csrf_token")
        if not token:
            m = re.search(
                r'name="csrf_token"\s+value="([^"]+)"'
                r'|value="([^"]+)"\s+name="csrf_token"',
                r.text,
            )
            token = (m.group(1) or m.group(2)) if m else ""

        if not token:
            return

        self.client.post(
            "/login",
            name="POST /login (attack)",
            data={
                "username": "user1",
                "password": "wrong-password",
                "csrf_token": token,
            },
            cookies={"csrf_token": token},
            headers={
                "User-Agent": "Locust-Login-Attack",
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": f"{self.host}/login",
                "Origin": self.host,
            },
        )