# WordPress 설치 가이드

## 시스템 사양
- **운영 체제:** Canonical Ubuntu
- **버전:** 22.04 Minimal
- **이미지:** Canonical-Ubuntu-22.04-Minimal-2024.10.06-0
- **인스턴스 유형:** VM.Standard.E2.1.Micro
- **OCPU 수:** 1
- **네트워크 대역폭 (Gbps):** 0.48
- **메모리 (GB):** 1
- **로컬 디스크:** 블록 스토리지 전용

---

## Oracle Cloud 초기 설정

### VNIC 설정
1. **Reserved Public IP 생성**
2. **VM에 할당된 기존 임시 IP 해제**
3. **Reserved IP 등록**
4. **Security List Ingress Rules 설정**
   - 포트 80 (HTTP)
   - 포트 443 (HTTPS)

### SSH 접속 설정
1. VM 생성 시 제공된 `key` 및 `key.pub` 파일을 안전하게 보관
2. `key.pub` 파일 내용을 VM Console에서 등록
3. 로컬 환경에서 다음 명령 실행:
   ```bash
   # 기존 SSH 키 제거 (필요한 경우)
   ssh-keygen -R <IP주소>
   
   # 키 파일 권한 설정
   chmod 600 <key_name>.key
   
   # SSH 접속
   ssh -i <key_name>.key ubuntu@<IP주소>
   ```

---

## WordPress 설치

### WordPress 설치 스크립트 실행
```bash
cd ~
curl -O https://raw.githubusercontent.com/nkimtnt/wp/main/wordpress-setup.sh
chmod +x wordpress-setup.sh
sudo ./wordpress-setup.sh
```

### MariaDB 설정
스크립트 실행 후 MariaDB 보안 설정을 진행합니다:
```bash
sudo mysql_secure_installation
```

#### 설정 과정:
1. `Enter current password for root:` → **그냥 Enter**
2. `Switch to unix_socket authentication [Y/n]:` → **Y**
3. `Change the root password? [Y/n]:` → **Y** (원하는 root 비밀번호 입력)
4. `Remove anonymous users? [Y/n]:` → **Y**
5. `Disallow root login remotely? [Y/n]:` → **Y**
6. `Remove test database and access to it? [Y/n]:` → **Y**
7. `Reload privilege tables now? [Y/n]:` → **Y**

#### WordPress 데이터베이스 생성:
```bash
sudo mysql -u root -p
```
```sql
CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'wordpress'@'localhost' IDENTIFIED BY '원하는비밀번호';
GRANT ALL ON wordpress.* TO 'wordpress'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

---

## 도메인 설정

### 가비아 (GABIA)에서 도메인 구매 및 설정
1. **도메인 구매**
2. **DNS 설정** → Cloudflare 네임서버로 변경

### Cloudflare 설정
1. **사이트 추가**
2. **DNS 레코드 설정**
   - `A` 레코드: 도메인 → 서버 IP
   - `CNAME` 레코드: `www` → 도메인

---

## SSL 인증서 발급

### 인증서 발급 전 주의사항
- **Cloudflare 프록시 기능을 비활성화** (일시적으로 `DNS만` 설정)

### Certbot을 이용한 SSL 인증서 발급
```bash
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

### 인증서 발급 완료 후
1. **Cloudflare 프록시 기능 다시 활성화**
2. **SSL/TLS 설정을 '전체(엄격)'으로 변경**

### 주의사항
- **SSL 인증서 발급 시 Cloudflare 프록시를 반드시 비활성화해야 합니다.**
- **Cloudflare 프록시 사용 시 SSL/TLS 설정은 반드시 '전체(엄격)' 모드여야 합니다.**


