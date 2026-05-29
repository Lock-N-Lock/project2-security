# 금융 서비스 기반 보안 이벤트 탐지 및 자동 대응 클라우드 인프라 구축
### 🗨️ 프로젝트 소개

> 
> 
> 
> 본 프로젝트는 AWS 기반 클라우드 환경에서 금융 서비스 형태의 데모 애플리케이션을 컨테이너로 배포하고, 로그인 실패 및 이체 요청 폭주와 같은 보안 이벤트를 실시간으로 탐지·시각화·알림·대응하는 운영 보안 자동화하는 DevSecOps 시스템을 구현하는 것을 목표로 함.
> 
> 단순한 웹 서비스 개발이 아니라, 클라우드 인프라 환경에서 서비스 운영 중 발생할 수 있는 이상 트래픽과 보안 이벤트를 감지하고, 자동 대응 및 복구 흐름까지 연결하는 데 중점을 둠.
> 

서비스 배포를 넘어, 보안 이벤트 발생 시 자동으로 탐지·대응·복구하는 클라우드 운영 보안 플랫폼을 구축함.

### 💠 팀명

- Lock & Lock

### 💠 팀원

- 신준한(팀장), 박정은, 이지윤, 임종원, 최상우

### 💠 역할 분담

`각 팀원의 역할과 책임`

- 신준한/박정은: AWS 구성, Terraform 코드 작성, Security Group 설계, Auto Scaling 연계 검토
- 최상우/임종원: FastAPI 금융 데모(로그인·조회·이체), PostgreSQL 연동, Prometheus Custom Metrics 제공, Dockerfile 작성 + ansible
- 임종원/신준한: GitHub Actions, Docker Hub/GHCR 연동, Blue-Green 배포 구조, SAST(Bandit) + Trivy + DAST(ZAP) + 워크플로 통합,
- 이지윤/박정은: Prometheus, Grafana, Alertmanager, Telegram 연동, Dashboard 구성, Alert Rule 작성
- 박정은/이지윤: Locust 부하 공격 시나리오, Nginx Rate Limit, fail2ban, 보안 이벤트 검증, 탐지→알림→대응 흐름 테스트 Health Check, 전환 및 Rollback 스크립트
