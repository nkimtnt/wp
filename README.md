# Oracle Cloud VM 워드프레스 자동 설치 스크립트

이 스크립트는 Oracle Cloud Free Tier VM에 워드프레스를 쉽게 설치하기 위한 자동화 도구입니다.

## 기능
- 시스템 업데이트 및 필수 패키지 설치
- 4GB 스왑 메모리 자동 설정
- Docker 및 Docker Compose 설치
- 워드프레스 및 MySQL 컨테이너 자동 설정
- 방화벽 자동 구성
- Cloudflare 연동을 통한 HTTPS 설정 가이드

## 사용 방법
### 스크립트 다운로드 및 실행

```bash
# 스크립트 다운로드
curl -O https://raw.githubusercontent.com/your-username/wordpress-oracle-setup/main/wordpress-setup.sh

# 실행 권한 부여
chmod +x wordpress-setup.sh

# 스크립트 실행
sudo ./wordpress-setup.sh# wp
