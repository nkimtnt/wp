#!/bin/bash

# WordPress 설치 스크립트 (직접 설치 방식)
# Ubuntu 22.04 LTS 미니멀 VM용

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
echo "===== 워드프레스 설치 설정 ====="
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

# 시스템 업데이트 및 vim 설치
echo -e "\n시스템 업데이트 및 vim 설치 중..."
apt update && apt upgrade -y
apt install -y vim

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

# 스왑 상태 확인
echo -e "\n스왑 상태:"
free -h

# MySQL 8.0 설치 및 설정
echo -e "\nMySQL 8.0 설치 및 설정 중..."
apt install -y mysql-server-8.0

# MySQL 서비스 시작 및 활성화
systemctl start mysql
systemctl enable mysql

# MySQL 초기 보안 설정
echo -e "\nMySQL 보안 설정 중..."
mysql --user=root <<_EOF_
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
_EOF_

# WordPress 데이터베이스 및 사용자 생성
echo -e "\nWordPress 데이터베이스 생성 중..."
mysql --user=root --password="${DB_ROOT_PASSWORD}" <<_EOF_
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
_EOF_

# MySQL 설정 테스트
echo -e "\nMySQL 설정 테스트 중..."
if mysql --user="${DB_USER}" --password="${DB_PASSWORD}" -e "USE ${DB_NAME}"; then
    echo "MySQL 설정이 성공적으로 완료되었습니다."
else
    echo "MySQL 설정 중 오류가 발생했습니다."
    exit 1
fi

# Apache 및 PHP 설치
echo -e "\nApache 및 PHP 설치 중..."
apt install -y apache2 \
    php \
    php-mysql \
    php-curl \
    php-gd \
    php-intl \
    php-mbstring \
    php-soap \
    php-xml \
    php-xmlrpc \
    php-zip

# Apache 설정
echo -e "\nApache 설정 중..."
cat > /etc/apache2/sites-available/wordpress.conf << EOL
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/wordpress
    ServerName localhost
    
    <Directory /var/www/wordpress>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOL

# WordPress 다운로드 및 설치
echo -e "\nWordPress 다운로드 및 설치 중..."
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz
rm -rf /var/www/wordpress
mv wordpress /var/www/
chown -R www-data:www-data /var/www/wordpress
chmod -R 755 /var/www/wordpress

# WordPress 설정 파일 생성
echo -e "\nWordPress 설정 파일 생성 중..."
cp /var/www/wordpress/wp-config-sample.php /var/www/wordpress/wp-config.php
sed -i "s/database_name_here/$DB_NAME/" /var/www/wordpress/wp-config.php
sed -i "s/username_here/$DB_USER/" /var/www/wordpress/wp-config.php
sed -i "s/password_here/$DB_PASSWORD/" /var/www/wordpress/wp-config.php

# WordPress 보안 키 생성 및 추가
echo -e "\nWordPress 보안 키 생성 중..."
SECURITY_KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
sed -i "/put your unique phrase here/d" /var/www/wordpress/wp-config.php
echo "$SECURITY_KEYS" >> /var/www/wordpress/wp-config.php

# .htaccess 파일 생성
echo -e "\n.htaccess 파일 생성 중..."
cat > /var/www/wordpress/.htaccess << EOL
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
EOL

# Apache 설정 활성화
echo -e "\nApache 설정 활성화 중..."
a2dissite 000-default.conf
a2ensite wordpress.conf
a2enmod rewrite
systemctl restart apache2

# 방화벽 설정
echo -e "\n방화벽 설정 중..."
if command -v ufw &> /dev/null; then
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    echo "방화벽이 설정되었습니다."
fi

# 서버 IP 주소 가져오기
SERVER_IP=$(hostname -I | awk '{print $1}')

# 설치 완료 메시지
echo -e "\n===========================================
워드프레스 설치가 완료되었습니다!
브라우저에서 다음 주소로 접속하세요: http://$SERVER_IP

MySQL 정보:
루트 비밀번호: $DB_ROOT_PASSWORD
데이터베이스: $DB_NAME
사용자: $DB_USER
비밀번호: $DB_PASSWORD

WordPress 설정 파일 위치: /var/www/wordpress/wp-config.php
===========================================

도움말:
- Apache 상태 확인: systemctl status apache2
- MySQL 상태 확인: systemctl status mysql
- Apache 에러 로그: tail -f /var/log/apache2/error.log
- Apache 액세스 로그: tail -f /var/log/apache2/access.log
"

# 보안 팁 추가
if [[ "$DB_ROOT_PASSWORD" == "rootpassword" || "$DB_PASSWORD" == "wordpress_password" ]]; then
    echo -e "\n경고: 기본 비밀번호를 사용하고 있습니다. 보안을 위해 비밀번호를 변경하는 것을 권장합니다."
fi

# Oracle Cloud 포트 안내
echo -e "\n참고: Oracle Cloud VM을 사용하는 경우 포트 $WP_PORT(HTTP 기본 포트)가 인그레스 규칙에서 허용되어 있는지 확인하세요."
