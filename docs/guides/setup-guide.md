# 초기 환경 세팅 가이드 (Lock & Lock / project2-security)

> 파일 위치 : ~/project2-security/docs/guides/setup-guide.md

> 대상: 자신의 vmware(예:proj-mgmt) (VMware, Rocky Linux 8)
> 목적: Terraform 작업 전, 팀원 각자 로컬 환경을 동일하게 맞춘다.
> 세 스크립트(`setup.sh` → `bootstrap_tailscale.sh` → `check.sh`)만 순서대로 실행하면 끝.

---

## 0. 사전 준비물 (개인별로 미리 발급)

| 키 | 발급처 | 형식 |
|---|---|---|
| AWS Access/Secret Key | AWS IAM → 본인 계정 | `AKIA...` / 시크릿 |
| Tailscale Auth Key | login.tailscale.com → Settings → Keys → Auth keys | `tskey-auth-...` (Reusable·Pre-approved ON 권장) |
| Tailscale API Key (선택) | 같은 화면 → API access tokens | `tskey-api-...` (서브넷 라우트 자동승인용) |
| Docker Hub Token | hub.docker.com → Account settings → Personal access tokens | `dckr_pat_...` |

> AWS 키는 **개인 계정** 기준입니다(공통 코드 + 개인 자격증명). 비용도 각자 계정에 청구됩니다.

---

## 1. 실행 순서 (3단계)

레포 루트(`~/project2-security`)에서 실행합니다.

### STEP 1 — 도구 설치 + 자격증명 등록

```bash
chmod +x setup.sh check.sh bootstrap_tailscale.sh   # 최초 1회 권한 부여
bash setup.sh
```

`setup.sh`가 자동으로 처리하는 것:
- AWS CLI v2 / Terraform / Ansible / Docker 설치 (이미 있으면 건너뜀)
- **AWS 자격증명** 확인 → 없으면 `aws configure` 실행 (개인 키 입력, region=ap-northeast-2)
- **Docker Hub 로그인** → `~/.dockerhub_token` 없으면 아이디·토큰 입력받아 생성 후 로그인
- 마지막에 docker 그룹이 현재 셸에 미반영이면 `newgrp docker`로 새 셸 진입 (종료: `exit`)

> 입력 프롬프트가 뜨면 안내에 따라 키를 붙여넣으면 됩니다. 토큰은 화면에 표시되지 않습니다(정상).

### STEP 2 — Tailscale 연결 (+ VXLAN 준비)

```bash
./bootstrap_tailscale.sh
```

자동으로 처리하는 것:
- `~/.tailscale_key` 없으면 Auth Key(필수) / API Key·tailnet 이름(선택) 입력받아 생성
- Tailscale 가입 + `172.16.1.0/24` 서브넷 광고 (hostname은 머신별 자동)
- API Key를 넣었으면 서브넷 라우트 **자동 승인**, 안 넣었으면 수동 승인 안내 출력
- VXLAN은 이 시점엔 **건너뜀**(`ENABLE_VXLAN=false`) — Bastion 생성 후 별도 적용

> TAILNET_NAME은 노드 이름(proj-mgmt)이 아니라 **가입 이메일 전체**(예: `you@gmail.com`)입니다.

### STEP 3 — 환경 점검

```bash
make check        # 또는 bash check.sh
```

`[1]~[5]`가 전부 ✅이면 준비 완료입니다.
`[6] VXLAN`은 이 단계에서 ⚠️가 **정상**입니다 (아래 2번 참고).

---

## 2. VXLAN은 왜 아직 ⚠️ 인가 (정상입니다)

VXLAN은 proj-mgmt와 **AWS Bastion 양쪽**이 있어야 성립합니다. 아직 `terraform apply` 전이라 Bastion이 없으므로 `ENABLE_VXLAN=false`로 두는 게 맞습니다.

Bastion 생성 후 적용 순서:

```bash
cd infra/terraform && terraform apply        # 1) Bastion 생성
terraform output bastion_ts_ip               # 2) Bastion Tailscale IP 확인
# 3) bootstrap_tailscale.sh 상단에서:
#      ENABLE_VXLAN="true"
#      AWS_BASTION_TS_IP="<위에서 확인한 100.x.x.x>"
./bootstrap_tailscale.sh                      # 4) 재실행 → vxlan0 생성
make check                                    # [6] 이 ✅ 로 바뀜
```

---

## 3. 시크릿 파일 관리

모든 개인 시크릿은 **홈 디렉터리(`~`) 아래, 권한 600, 레포 바깥**에 둡니다. 절대 커밋하지 않습니다.

| 시크릿 | 위치 | 내용 |
|---|---|---|
| AWS 키 | `~/.aws/credentials`, `~/.aws/config` | access/secret/region/output |
| Tailscale 키(통합) | `~/.tailscale_key` | `TAILSCALE_AUTHKEY` / `TAILSCALE_API_KEY` / `TAILNET_NAME` |
| Docker Hub 토큰 | `~/.dockerhub_token` | `DOCKERHUB_USER` / `DOCKERHUB_TOKEN` |

`.gitignore`에 `.tailscale_key`, `.dockerhub_token`, `.aws/`가 등록돼 있어 실수 커밋을 막습니다.

---

## 4. 자주 겪는 문제 (트러블슈팅)

| 증상 | 원인 / 해결 |
|---|---|
| `Permission denied`로 스크립트 실행 안 됨 | `chmod +x setup.sh check.sh bootstrap_tailscale.sh` |
| `docker info` 권한 에러 | docker 그룹 미반영 → `newgrp docker` 또는 재로그인 |
| Tailscale `... offline` 표시 | coordination server 동기화 지연 가능 → 잠시 후 `tailscale status` 재확인. 지속되면 `sudo systemctl restart tailscaled` |
| `Some peers are advertising routes but --accept-routes is false` | **정상**. VSCode 끊김 방지를 위한 의도된 설정 |
| 서브넷 라우트 자동승인 실패 | `~/.tailscale_key`의 `TAILNET_NAME`(이메일) 확인, 또는 Admin 콘솔에서 `172.16.1.0/24` 수동 체크 |
| 머신 hostname이 `localhost` 등으로 등록됨 | `sudo hostnamectl set-hostname proj-mgmt-본인` 후 재실행 |

---

## 5. 한 번에 보는 실행 요약

```bash
cd ~/project2-security
chmod +x setup.sh check.sh bootstrap_tailscale.sh   # 최초 1회
bash setup.sh             # 도구 + AWS + Docker Hub
./bootstrap_tailscale.sh  # Tailscale (+ VXLAN 준비)
make check                # 점검 ([6] VXLAN ⚠️ 는 정상)
```