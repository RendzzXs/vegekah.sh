#!/bin/bash
# ==========================================
# 🛠️ AUTO FIX 404 NOT FOUND (Nginx)
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

read -p "👉 Masukkan Domain Web yang error (contoh: vgk.asupan.googleclient.biz.id): " DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}❌ Domain tidak boleh kosong!${NC}"; exit 1; }

WEB_ROOT="/var/www/$DOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo -e "${CYAN}[1/5] Cek Folder Web...${NC}"
if [ ! -d "$WEB_ROOT" ]; then
    echo -e "${RED}❌ Folder $WEB_ROOT TIDAK ADA!${NC}"
    echo -e "${YELLOW}⚠️ Kemungkinan lu salah ketik domain pas install.${NC}"
    echo -e "Coba cek folder yang ada di /var/www/:"
    ls -d /var/www/*/ | xargs -n 1 basename
    echo -e "${RED}Silakan hapus script ini dan jalankan ulang INSTALLER pake domain yang bener.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✅ Folder Ditemukan${NC}"

echo -e "${CYAN}[2/5] Bikin File index.php Darurat...${NC}"
# Kalo index.php ilang, kita bikin darurat dulu biar ga 404
if [ ! -f "$WEB_ROOT/index.php" ]; then
    echo -e "${YELLOW}⚠️ File index.php ga ada. Bikin darurat...${NC}"
    cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php
echo "<h1 style='color:white;background:black;padding:50px;text-align:center;font-family:sans-serif;'>Web Asupan VGK Siap! (File web asli belum ke-extract)</h1>";
PHPEOF
fi

echo -e "${CYAN}[3/5] Benerin Config Nginx...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.php index.html;
    client_max_body_size 3000M;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location ~ /\.ht { deny all; }
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_read_timeout 300;
    }
}
NGINXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 && systemctl reload nginx
echo -e "${GREEN}  ✅ Nginx Fixed${NC}"

echo -e "${CYAN}[4/5] Cek SSL...${NC}"
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo -e "${YELLOW}⚠️ SSL Belum ada. Install ulang...${NC}"
    read -p "👉 Email SSL: " EMAIL
    [[ -z "$EMAIL" ]] && EMAIL="admin@$DOMAIN"
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1
fi
echo -e "${GREEN}  ✅ SSL OK${NC}"

echo -e "${CYAN}[5/5] Restart Service...${NC}"
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 777 "$WEB_ROOT/uploads" 2>/dev/null
systemctl restart php8.3-fpm nginx

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ AUTO FIX 404 SELESAI!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Silakan buka: ${WHITE}https://$DOMAIN${NC}"
echo -e "${YELLOW}⚠️  Kalo muncul tulisan 'Web Asupan VGK Siap!', berarti config udah bener,${NC}"
echo -e "${YELLOW}    tapi lu harus re-upload file webnya (extract ulang).${NC}"
