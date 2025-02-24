#!/bin/bash

# 루트 권한 확인
if [ "$(id -u)" -ne 0 ]; then
    echo "이 스크립트는 루트 권한으로 실행해야 합니다. sudo를 사용하세요."
    exit 1
fi

# 기본 시스템 설정
echo -e "\n=== 기본 시스템 설정 ==="
apt update && apt upgrade -y
apt install -y vim nano ufw iputils-ping dnsutils net-tools curl

# 시간대 설정
echo -e "\n=== 시간대 설정 ==="
timedatectl set-timezone Asia/Seoul
echo "현재 시스템 시간 설정:"
timedatectl status

# 스왑 설정
echo -e "\n=== 스왑 파일 설정 ==="
if [ ! -f /swapfile ]; then
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "스왑 파일이 생성되었습니다."
else
    echo "스왑 파일이 이미 존재합니다."
fi

echo "스왑 상태:"
swapon --show
free -h

# UFW 설정
echo -e "\n=== 방화벽 설정 ==="
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
echo "UFW 상태:"
ufw status

# MariaDB 설치 (설정은 제외)
echo -e "\n=== MariaDB 설치 ==="
apt install -y mariadb-server
systemctl start mariadb
systemctl enable mariadb
echo "MariaDB가 설치되었습니다. 보안 설정을 위해 'sudo mysql_secure_installation'을 실행하세요."

# PHP 8.2 설치
echo -e "\n=== PHP 8.2 설치 ==="
apt install -y software-properties-common
add-apt-repository ppa:ondrej/php -y
apt update
apt install -y php8.2-fpm php8.2-mysql php8.2-curl php8.2-gd php8.2-mbstring php8.2-xml php8.2-xmlrpc php8.2-soap php8.2-intl php8.2-zip

# PHP 설정
echo -e "\n=== PHP 설정 ==="
PHP_INI="/etc/php/8.2/fpm/php.ini"
# awk를 사용하여 2번째 occurrence만 변경
awk '!/^;/ && /short_open_tag = Off/ {count++} count==2 {sub(/short_open_tag = Off/, "short_open_tag = On")} {print}' $PHP_INI > tmp.ini && mv tmp.ini $PHP_INI
sed -i 's/^memory_limit.*/memory_limit = 256M/' $PHP_INI
sed -i 's/^;cgi.fix_pathinfo.*/cgi.fix_pathinfo = 0/' $PHP_INI
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 100M/' $PHP_INI
sed -i 's/^post_max_size.*/post_max_size = 101M/' $PHP_INI
sed -i 's/^max_execution_time.*/max_execution_time = 360/' $PHP_INI
sed -i 's/^;date.timezone.*/date.timezone = Asia/Seoul/' $PHP_INI

# Nginx 설치
echo -e "\n=== Nginx 설치 ==="
apt install -y nginx

# WordPress 다운로드 및 설정
echo -e "\n=== WordPress 설치 ==="
mkdir -p /var/www/wordpress
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz
cp -R wordpress/* /var/www/wordpress/
chown -R www-data:www-data /var/www/wordpress
chmod -R 755 /var/www/wordpress

# Nginx 설정
echo -e "\n=== Nginx 설정 ==="
read -p "도메인 이름을 입력하세요 (예: example.com): " domain_name

cat > /etc/nginx/sites-available/wordpress << EOL
server {
    listen 80;
    listen [::]:80;
    server_name www.${domain_name} ${domain_name};
    root /var/www/wordpress;
    index index.php;
    
    location ~ \.(gif|jpg|png)$ {
        add_header Vary "Accept-Encoding";
        add_header Cache-Control "public, no-transform, max-age=31536000";
    }
    
    location ~* \.(css|js)$ {
        add_header Cache-Control "public, max-age=604800";
        log_not_found off;
        access_log off;
    }
    
    location ~*.(mp4|ogg|ogv|svg|svgz|eot|otf|woff|woff2|ttf|rss|atom|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf|cur)$ {
        add_header Cache-Control "max-age=31536000";
        access_log off;
    }
    
    charset utf-8;
    server_tokens off;
    client_max_body_size 100M;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOL

ln -sf /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# SSL 인증서 설치를 위한 certbot 설치
echo -e "\n=== SSL 인증서 도구 설치 ==="
apt install -y python3-certbot-nginx

# 서비스 재시작
echo -e "\n=== 서비스 재시작 ==="
systemctl restart php8.2-fpm
systemctl restart nginx

echo -e "\n=== 설치 완료 ==="
echo "WordPress 파일이 설치되었습니다."
echo -e "\n다음 단계:"
echo "1. MariaDB 보안 설정을 위해 'sudo mysql_secure_installation' 실행"
echo "2. WordPress 데이터베이스 및 사용자 생성"
echo "3. wp-config.php 설정"
echo "4. DNS 설정 완료 후 SSL 인증서 발급:"
echo "   sudo certbot --nginx -d ${domain_name} -d www.${domain_name}"
echo "5. Cloudflare 설정 시 주의사항:"
echo "   - SSL 인증서 발급 시 Cloudflare 프록시 기능을 비활성화"
echo "   - 인증서 발급 완료 후 프록시 활성화 시 SSL/TLS 설정을 '전체(엄격)'으로 설정"
