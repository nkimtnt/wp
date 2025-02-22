#!/bin/bash

# 워드프레스 도커 자동 설치 스크립트 (사용자 입력 방식)
# Oracle Free Tier x86 VM용 + Cloudflare 설정 안내 포함

# 루트 권한 확인
if [ "$(id -u)" -ne 0 ]; then
    echo "이 스크립트는 루트 권한으로 실행해야 합니다. sudo를 사용하세요."
    exit 1
fi

# 환경 변수 기본값 설정
SWAP_SIZE="4G" # 스왑 사이즈는 고정값으로 설정
DB_ROOT_PASSWORD="rootpassword"
DB_NAME="wordpress"
DB_USER="wordpress"
DB_PASSWORD="wordpress_password"
WP_PORT="8081" # 웹 서버 포트 8081로 고정

# 사용자 입력 받기
echo "===== 워드프레스 도커 설치 설정 ====="
echo "기본값을 사용하려면 입력 없이 Enter 키를 누르세요."

# 도메인 설정
read -p "워드프레스에 사용할 도메인 (Cloudflare 설정용, 없으면 빈칸): " DOMAIN_NAME

# 데이터베이스 설정
read -p "MySQL 루트 비밀번호 [기본값: $DB_ROOT_PASSWORD]: " input
DB_ROOT_PASSWORD=${input:-$DB_ROOT_PASSWORD}

read -p "워드프레스 데이터베이스 이름 [기본값: $DB_NAME]: " input
DB_NAME=${input:-$DB_NAME}

read -p "워드프레스 데이터베이스 사용자 [기본값: $DB_USER]: " input
DB_USER=${input:-$DB_USER}

read -p "워드프레스 데이터베이스 비밀번호 [기본값: $DB_PASSWORD]: " input
DB_PASSWORD=${input:-$DB_PASSWORD}

# 입력 정보 확인
echo -e "\n===== 설정 정보 확인 ====="
echo "스왑 파일 크기: $SWAP_SIZE (자동 설정)"
echo "MySQL 루트 비밀번호: $DB_ROOT_PASSWORD"
echo "워드프레스 데이터베이스 이름: $DB_NAME"
echo "워드프레스 데이터베이스 사용자: $DB_USER"
echo "워드프레스 데이터베이스 비밀번호: $DB_PASSWORD"
echo "워드프레스 웹 서버 포트: $WP_PORT (고정값)"
if [ -n "$DOMAIN_NAME" ]; then
    echo "사용할 도메인: $DOMAIN_NAME"
else
    echo "도메인: 설정되지 않음"
fi

read -p "이 설정으로 계속하시겠습니까? (y/n) " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "설치가 취소되었습니다."
    exit 1
fi

# 시스템 업데이트
echo -e "\n시스템 업데이트 중..."
apt update && apt upgrade -y

# 스왑 파일 생성
echo -e "\n$SWAP_SIZE 스왑 파일 생성 중..."
if [ ! -f /swapfile ]; then
    fallocate -l $SWAP_SIZE /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    sysctl -p
    echo "스왑 파일이 생성되었습니다."
else
    echo "스왑 파일이 이미 존재합니다."
fi

# 스왑 상태 확인
echo -e "\n스왑 상태:"
free -h

# 기본 도구 설치
echo -e "\n기본 도구 설치 중..."
apt install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

# 도커 설치
echo -e "\n도커 설치 중..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
    echo "도커가 설치되었습니다."
else
    echo "도커가 이미 설치되어 있습니다."
fi

# Docker Compose 설치
echo -e "\nDocker Compose 설치 중..."
if ! command -v docker-compose &> /dev/null; then
    curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose가 설치되었습니다."
else
    echo "Docker Compose가 이미 설치되어 있습니다."
fi

# 워드프레스 디렉토리 생성
echo -e "\n워드프레스 디렉토리 생성 중..."
mkdir -p /opt/wordpress
cd /opt/wordpress

# Docker Compose 구성 파일 생성
echo -e "\nDocker Compose 구성 파일 생성 중..."
cat > /opt/wordpress/docker-compose.yml << EOL
version: '3'

services:
  db:
    image: mysql:5.7
    volumes:
      - db_data:/var/lib/mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    command: '--default-authentication-plugin=mysql_native_password'

  wordpress:
    depends_on:
      - db
    image: wordpress:latest
    ports:
      - "${WP_PORT}:80"
    restart: always
    volumes:
      - wp_content:/var/www/html/wp-content
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD}
      WORDPRESS_DB_NAME: ${DB_NAME}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost"]
      interval: 1m
      timeout: 10s
      retries: 3

volumes:
  db_data:
  wp_content:
EOL

# 워드프레스 컨테이너 시작
echo -e "\n워드프레스 컨테이너 시작 중..."
cd /opt/wordpress
docker-compose up -d

# 방화벽 설정
echo -e "\n방화벽 설정 중..."
if command -v ufw &> /dev/null; then
    ufw allow 22/tcp
    ufw allow ${WP_PORT}/tcp
    ufw --force enable
    echo "방화벽이 설정되었습니다."
fi

# 서버 IP 주소 가져오기
SERVER_IP=$(hostname -I | awk '{print $1}')

# Cloudflare 설정 가이드 파일 생성
if [ -n "$DOMAIN_NAME" ]; then
    cat > /opt/wordpress/cloudflare_setup_guide.txt << EOL
===== Cloudflare 설정 가이드 =====

워드프레스가 설치되었습니다. 이제 Cloudflare를 통해 HTTPS를 설정하는 방법입니다.

1단계: Cloudflare 계정 설정
--------------------------------
1. Cloudflare 계정이 없다면 https://dash.cloudflare.com/sign-up에서 가입하세요.
2. Cloudflare 대시보드에서 "사이트 추가" 버튼을 클릭하세요.
3. 도메인 이름 ($DOMAIN_NAME)을 입력하고 "사이트 추가" 버튼을 클릭하세요.
4. 무료 플랜을 선택하세요.
5. Cloudflare가 기존 DNS 레코드를 스캔할 때까지 기다리세요.

2단계: DNS 레코드 설정
--------------------------------
1. Cloudflare가 발견한 DNS 레코드를 확인하고 계속 진행하세요.
2. 아래 DNS 레코드를 추가하세요:
   - 유형: A
   - 이름: @ (또는 하위 도메인을 사용하는 경우 해당 하위 도메인)
   - IPv4 주소: $SERVER_IP
   - 프록시 상태: 프록시됨 (주황색 구름 아이콘이 활성화되어야 함)

3. "계속" 버튼을 클릭하세요.

3단계: 네임서버 변경
--------------------------------
1. Cloudflare가 제공하는 네임서버를 메모하세요.
2. 도메인 등록 대행사(예: GoDaddy, Namecheap 등)의 관리 패널로 이동하세요.
3. DNS 설정에서 네임서버를 Cloudflare에서 제공한 네임서버로 변경하세요.
4. 변경 사항이 적용되려면 최대 24시간이 걸릴 수 있습니다.

4단계: SSL/TLS 설정
--------------------------------
1. Cloudflare 대시보드에서 "$DOMAIN_NAME" 도메인을 선택하세요.
2. "SSL/TLS" 탭으로 이동하세요.
3. SSL/TLS 암호화 모드를 "Full"로 설정하세요.
4. "Edge 인증서" 탭에서 "항상 HTTPS 사용"을 켜세요.

5단계: 워드프레스 설정 업데이트
--------------------------------
네임서버 변경이 적용된 후 (보통 몇 시간 이내):

1. 워드프레스 관리자 페이지(http://$SERVER_IP:$WP_PORT/wp-admin)에 접속하세요.
2. "설정" > "일반"으로 이동하세요.
3. "WordPress 주소(URL)"와 "사이트 주소(URL)"를 다음과 같이 변경하세요:
   - http://$DOMAIN_NAME에서 https://$DOMAIN_NAME으로 변경
4. "변경 사항 저장" 버튼을 클릭하세요.

이제 https://$DOMAIN_NAME으로 안전하게 워드프레스 사이트에 접속할 수 있습니다!

주의사항:
- Cloudflare 무료 플랜은 대부분의 개인 블로그에 충분합니다.
- SSL 인증서는 Cloudflare에서 자동으로 관리됩니다.
- 워드프레스에서 HTTPS로 전환한 후 혼합 콘텐츠 오류가 발생할 수 있습니다. 이 경우 "Really Simple SSL" 플러그인을 사용하면 대부분의 문제가 해결됩니다.
EOL
    echo -e "\nCloudflare 설정 가이드가 /opt/wordpress/cloudflare_setup_guide.txt에 저장되었습니다."
fi

# 설치 완료 메시지
echo -e "\n===========================================
워드프레스 설치가 완료되었습니다!
브라우저에서 다음 주소로 접속하세요: http://$SERVER_IP:$WP_PORT

MySQL 정보:
루트 비밀번호: $DB_ROOT_PASSWORD
데이터베이스: $DB_NAME
사용자: $DB_USER
비밀번호: $DB_PASSWORD

설정 파일 위치: /opt/wordpress/docker-compose.yml
===========================================

도움말:
- 컨테이너 상태 확인: sudo docker-compose -f /opt/wordpress/docker-compose.yml ps
- 컨테이너 중지: sudo docker-compose -f /opt/wordpress/docker-compose.yml stop
- 컨테이너 시작: sudo docker-compose -f /opt/wordpress/docker-compose.yml start
- 로그 확인: sudo docker-compose -f /opt/wordpress/docker-compose.yml logs
"

# Cloudflare 안내
if [ -n "$DOMAIN_NAME" ]; then
    echo -e "\n=== Cloudflare 설정 안내 ===
Cloudflare 설정 방법은 다음 파일에서 확인할 수 있습니다:
cat /opt/wordpress/cloudflare_setup_guide.txt

Cloudflare 설정이 완료되면 https://$DOMAIN_NAME 주소로 접속할 수 있습니다."
else
    echo -e "\n도메인을 설정하지 않았습니다. 나중에 Cloudflare를 설정하려면 도메인이 필요합니다."
fi

# 보안 팁 추가
if [[ "$DB_ROOT_PASSWORD" == "rootpassword" || "$DB_PASSWORD" == "wordpress_password" ]]; then
    echo -e "\n경고: 기본 비밀번호를 사용하고 있습니다. 보안을 위해 비밀번호를 변경하는 것을 권장합니다."
fi

# Oracle Cloud 포트 안내
echo -e "\n참고: Oracle Cloud VM을 사용하는 경우 포트 $WP_PORT가 인그레스 규칙에서 허용되어 있는지 확인하세요."
