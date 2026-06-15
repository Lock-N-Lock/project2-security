# security/locust/login_attack.py

from locust import HttpUser, task, constant


class LoginAttackUser(HttpUser):

    wait_time = constant(0)

    @task
    def brute_force_login(self):
        self.client.post(
            "/login",
            headers={
                "User-Agent": "Locust-Login-Attack"
            },
            json={
                "username": "user1",
                "password": "wrong-password"
            }
        )