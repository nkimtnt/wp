
# 워드프레스 도커 자동 설치 스크립트 (MySQL 8.0, 포트 80)
# Oracle VM에 최적화된 버전

# 루트 권한 확인
if [ "$(id -u)" -ne 0 ]; then
    echo "이 스크립트는 루트 권한으로 실행해야 합니다. sudo를 사용하세요."
    exit 1
fi

# 환경 변수 기본값 설정
SWAP_SIZE="4G"
DB_ROOT_PASSWORD="rootpassword"
DB_NAME="wordpress"
DB_USER="wordpress"
DB_PASSWORD="wordpress_password"
WP_PORT="80"

# 사용자 입력 받기
echo "===== 워드프레스 도커 설치 설정 ====="
echo "기본값을 사용하려면 입력 없이 Enter 키를 누르세요."

# 데이터베이스 설정
read -p "MySQL 루트 비밀번호 [기본값: $DB_ROOT_PASSWORD]: " input
DB_ROOT_PASSWORD=${input:-$DB_ROOT_PASSWORD}

read -p "워드프레스 데이터베이스 이름 [기본값: $DB_NAME]: " input
DB_NAME=${input:-$DB_NAME}

read -p "워드프레스 데이터베이스 사용자 [기본값: $DB_USER]: " input
DB_USER=${input:-$DB_USER}

read -p "워드프레스 데이터베이스 비밀번호 [기본값: $DB_PASSWORD]: " input
DB_PASSWORD=${input:-$DB_PASSWORD}

# 설정 정보 확인
echo -e "\n===== 설정 정보 확인 ====="
echo "스왑 파일 크기: $SWAP_SIZE"
echo "MySQL 루트 비밀번호: $DB_ROOT_PASSWORD"
echo "워드프레스 데이터베이스 이름: $DB_NAME"
echo "워드프레스 데이터베이스 사용자: $DB_USER"
echo "워드프레스 데이터베이스 비밀번호: $DB_PASSWORD"
echo "워드프레스 웹 서버 포트: $WP_PORT"

read -p "이 설정으로 계속하시겠습니까? (y/n) " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "설치가 취소되었습니다."
    exit 1
fi

# 시스템 업데이트
echo -e "\n시스템 업데이트 중..."
apt update && apt upgrade -y

# 기본 도구 설치 (UFW 포함)
echo -e "\n기본 도구 설치 중..."
apt install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common ufw vim

# 시간대 설정
echo -e "\n시스템 시간대를 Asia/Seoul로 설정 중..."
timedatectl set-timezone Asia/Seoul
echo "현재 시스템 시간 설정:"
timedatectl status

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

# 워드프레스 디렉토리 생성 및 준비
echo -e "\n워드프레스 디렉토리 생성 중..."
mkdir -p /opt/wordpress/wp-content
chmod 755 /opt/wordpress/wp-content
chown www-data:www-data /opt/wordpress/wp-content

# 서버 IP 주소 가져오기
SERVER_IP=$(hostname -I | awk '{print $1}')

# Docker Compose 구성 파일 생성
echo -e "\nDocker Compose 구성 파일 생성 중..."
cat > /opt/wordpress/docker-compose.yml << EOL
version: '3'

services:
  db:
    image: mysql:8.0
    volumes:
      - db_data:/var/lib/mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    command: >
      --default-authentication-plugin=caching_sha2_password
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci

  wordpress:
    depends_on:
      - db
    image: wordpress:latest
    ports:
      - "${WP_PORT}:80"
    restart: always
    volumes:
      - ./wp-content:/var/www/html/wp-content
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD}
      WORDPRESS_DB_NAME: ${DB_NAME}
      WORDPRESS_CONFIG_EXTRA: |
        define('WP_HOME','http://${SERVER_IP}');
        define('WP_SITEURL','http://${SERVER_IP}');
    user: "www-data:www-data"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost"]
      interval: 1m
      timeout: 10s
      retries: 3

volumes:
  db_data:
EOL

# 워드프레스 컨테이너 시작
echo -e "\n워드프레스 컨테이너 시작 중..."
cd /opt/wordpress
docker-compose up -d

# 데이터베이스 연결 테스트
echo -e "\n데이터베이스 연결 테스트 중..."
for i in {1..30}; do
    if docker-compose exec -T db mysql -u root -p${DB_ROOT_PASSWORD} -e "SHOW DATABASES;" > /dev/null 2>&1; then
        echo "데이터베이스 연결 성공!"
        break
    else
        echo "데이터베이스 연결 대기 중... (시도 $i/30, 5초 간격)"
        sleep 5
    fi
done

if [ $i -eq 30 ]; then
    echo "데이터베이스 연결 실패. 컨테이너를 중지하고 로그를 확인합니다."
    docker-compose logs db
    echo "컨테이너를 중지하시겠습니까? (y/n)"
    read -p "> " stop_containers
    if [[ $stop_containers == [yY] ]]; then
        docker-compose down
        echo "컨테이너가 중지되었습니다."
    fi
    exit 1
fi

# 방화벽 설정
echo -e "\n방화벽 설정 중..."
# UFW 기본 설정
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow ${WP_PORT}/tcp
ufw --force enable
echo "방화벽이 설정되었습니다."

# 권한 재설정
echo -e "\n권한 설정 중..."
chown -R www-data:www-data /opt/wordpress/wp-content
chmod -R 755 /opt/wordpress/wp-content

# 설치 완료 메시지
echo -e "\n===========================================
워드프레스 설치가 완료되었습니다!
브라우저에서 다음 주소로 접속하세요: http://$SERVER_IP

MySQL 정보:
루트 비밀번호: $DB_ROOT_PASSWORD
데이터베이스: $DB_NAME
사용자: $DB_USER
비밀번호: $DB_PASSWORD

설정 파일 위치: /opt/wordpress/docker-compose.yml

도움말:
- 컨테이너 상태 확인: cd /opt/wordpress && sudo docker-compose ps
- 컨테이너 중지: cd /opt/wordpress && sudo docker-compose stop
- 컨테이너 시작: cd /opt/wordpress && sudo docker-compose start
- 로그 확인: cd /opt/wordpress && sudo docker-compose logs
- 권한 문제 발생 시: sudo chown -R www-data:www-data /opt/wordpress/wp-content
===========================================
"

# Oracle Cloud 포트 안내
echo -e "\n참고: Oracle Cloud VM을 사용하는 경우 포트 $WP_PORT(HTTP 기본 포트)가 인그레스 규칙에서 허용되어 있는지 확인하세요."
