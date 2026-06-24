# security/locust/flood_attack.py

from locust import HttpUser, task, constant


class FloodAttackUser(HttpUser):

    wait_time = constant(0)

    @task
    def flood_api(self):
        self.client.get(
            "/api/account",
            headers={
                "User-Agent": "Locust-Flood-Attack"
            }
        )