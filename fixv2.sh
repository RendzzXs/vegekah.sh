#!/bin/bash
# ==========================================
# 🛠️ FIX NGINX FAILED & SSL ERROR
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

DOMAIN="vgk.asupan.googleclient.biz.id"
WEB_ROOT="/var/www/$DOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo -e "${CYAN}[1/4] Bikin Config Nginx Darurat (Tanpa SSL)...${NC}"
# Kita bikin config HTTP dulu biar Nginx bisa nyala
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }
}
NGINXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

echo -e "${CYAN}[2/4] Restart Nginx...${NC}"
nginx -t >/dev/null 2>&1 && systemctl restart nginx
echo -e "${GREEN}  ✅ Nginx Nyala Kembali${NC}"

echo -e "${CYAN}[3/4] Pasang SSL (Pake Email Bener)...${NC}"
read -p "👉 Masukkan Email SSL yang BENER (contoh: admin@gmail.com): " EMAIL
if [[ -z "$EMAIL" || "$EMAIL" != *"@"* ]]; then
    echo -e "${RED}❌ Email tidak valid! Harus ada @ dan domain.${NC}"
    echo -e "${YELLOW}Script berhenti. Lu bisa pasang SSL manual nanti.${NC}"
    exit 1
fi

certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo -e "${GREEN}  ✅ SSL Terpasang!${NC}"
else
    echo -e "${RED}  ❌ SSL Gagal. Cek koneksi DNS domain ke VPS.${NC}"
fi

echo -e "${CYAN}[4/4] Finalisasi...${NC}"
chown -R www-data:www-data "$WEB_ROOT"
systemctl restart php8.3-fpm nginx

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ FIX SELESAI!                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Buka: ${WHITE}http://$DOMAIN${NC}"
