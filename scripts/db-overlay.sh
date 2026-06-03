# =============================================================
# db-overlay.sh — AWS DB EC2를 VXLAN overlay 종단으로 합류 (㉠)
#  Tailscale 가입 + vxlan0(10.10.10.3) + proj-mgmt 로 FDB
#  목적: proj-mgmt(replica) ↔ AWS DB(primary) L2 직결 → 스트리밍 복제
#  파일위치 : ~/project2-security/scripts/db-overlay.sh
#  실행     : TS_AUTHKEY=tskey-xxx bash db-overlay.sh   (Ansible 주입 권장)
# =============================================================

#!/bin/bash
set -euo pipefail

OVERLAY_IP="10.10.10.3/24"
VNI=100
PEER_HOST="proj-mgmt"
AUTHKEY="${TS_AUTHKEY:-}"   # user_data 아님 — Ansible/환경변수로 주입

# 1) Tailscale 가입 (멱등, accept-routes=false 유지)
if ! tailscale status >/dev/null 2>&1; then
  [ -n "$AUTHKEY" ] || { echo "TS_AUTHKEY 필요"; exit 1; }
  tailscale up --authkey "$AUTHKEY" --hostname lb-db --accept-routes=false
fi

# 2) proj-mgmt 의 Tailscale IP 동적 조회 (하드코딩 X)
PEER_TS_IP=$(tailscale status | awk -v p="$PEER_HOST" '$2==p {print $1; exit}')
[ -n "$PEER_TS_IP" ] || { echo "tailnet에서 $PEER_HOST 못 찾음"; exit 1; }

# 3) VXLAN 종단 생성 (멱등)
if ! ip link show vxlan0 >/dev/null 2>&1; then
  ip link add vxlan0 type vxlan id "$VNI" dev tailscale0 dstport 4789 nolearning
  ip addr add "$OVERLAY_IP" dev vxlan0
  ip link set vxlan0 up
fi

# 4) proj-mgmt 방향 FDB(플러드) 엔트리
bridge fdb append 00:00:00:00:00:00 dev vxlan0 dst "$PEER_TS_IP" 2>/dev/null || true

ip -4 addr show vxlan0
echo "DB overlay up: 10.10.10.3 ↔ $PEER_HOST($PEER_TS_IP)"