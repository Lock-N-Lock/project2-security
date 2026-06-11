# ── monitoring/tailscale-sd/Dockerfile ──
FROM python:3.11-slim
COPY tailscale_sd.py /app/tailscale_sd.py
EXPOSE 9999
CMD ["python", "/app/tailscale_sd.py"]