#!/usr/bin/env bash
# Scan to PDF API — serverga o'rnatish / yangilash (root sifatida, VPS'da ishga tushiriladi).
# Kutiladi: /tmp/scan-api.tgz (server/ papkasi, node_modules'siz)
#           /tmp/anthropic_key.txt (faqat birinchi o'rnatishda yoki kalit almashganda)
#           SUPPORT_EMAIL muhit o'zgaruvchisi (maxfiylik sahifasi uchun)
set -euo pipefail

APP=/opt/scan-api
DOMAIN=scanapi.argosacademy.uz
EMAIL="${SUPPORT_EMAIL:?SUPPORT_EMAIL kerak}"

# 1) Tizim foydalanuvchisi va papka (argosacademy'dan ajratilgan)
id scanapi >/dev/null 2>&1 || useradd --system --home "$APP" --shell /usr/sbin/nologin scanapi
mkdir -p "$APP/data"

# 2) Kod (zaxira bilan)
if [ -d "$APP/src" ]; then
  B=/var/backups/scan-api/pre-$(date +%Y%m%d-%H%M%S)
  mkdir -p "$B" && cp -a "$APP/src" "$APP/public" "$APP/package.json" "$B/" 2>/dev/null || true
  echo "zaxira: $B"
fi
tar -xzf /tmp/scan-api.tgz -C "$APP"
sed -i "s/__SUPPORT_EMAIL__/$EMAIL/g" "$APP/public/privacy.html" "$APP/public/delete-account.html"
cd "$APP" && npm ci --omit=dev --no-audit --no-fund >/dev/null && echo "npm: ok"

# 3) .env (kalit faylidan; kalit ekranga chiqarilmaydi)
if [ ! -f "$APP/.env" ]; then
  cp "$APP/.env.example" "$APP/.env"
fi
if [ -f /tmp/anthropic_key.txt ]; then
  KEY=$(tr -d ' \r\n' < /tmp/anthropic_key.txt)
  case "$KEY" in sk-ant-*) ;; *) echo "XATO: kalit 'sk-ant-' bilan boshlanmaydi"; exit 1;; esac
  sed -i "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=$KEY|" "$APP/.env"
  shred -u /tmp/anthropic_key.txt 2>/dev/null || rm -f /tmp/anthropic_key.txt
  unset KEY
  echo "kalit: .env ga yozildi"
fi
chown -R scanapi:scanapi "$APP"
chmod 600 "$APP/.env"

# 4) systemd
NODE_BIN=$(command -v node)
sed "s|/usr/bin/node|$NODE_BIN|" "$APP/deploy/scan-api.service" > /etc/systemd/system/scan-api.service
systemctl daemon-reload
systemctl enable --now scan-api >/dev/null 2>&1
systemctl restart scan-api

# 5) nginx
# Faqat birinchi marta — keyin certbot qo'shgan SSL qismi saqlanib qolishi kerak
[ -f /etc/nginx/sites-available/scanapi ] || install -m 644 "$APP/deploy/nginx-scanapi.conf" /etc/nginx/sites-available/scanapi
# Uzun domen nomlari uchun joy (standart 32 — scanapi.argosacademy.uz sig'maydi)
if ! grep -qE '^[[:space:]]*server_names_hash_bucket_size' /etc/nginx/nginx.conf; then
  cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak-scanapi
  if grep -qE '#[[:space:]]*server_names_hash_bucket_size' /etc/nginx/nginx.conf; then
    sed -i -E 's/#[[:space:]]*server_names_hash_bucket_size[[:space:]]+[0-9]+;/server_names_hash_bucket_size 64;/' /etc/nginx/nginx.conf
  else
    sed -i '0,/http {/s//http {\n\tserver_names_hash_bucket_size 64;/' /etc/nginx/nginx.conf
  fi
  echo "nginx: server_names_hash_bucket_size 64"
fi
ln -sf /etc/nginx/sites-available/scanapi /etc/nginx/sites-enabled/scanapi
# Sozlama xato bo'lsa — yangi saytni olib tashlaymiz, nginx doim ishchi holatda qoladi
if ! nginx -t; then
  rm -f /etc/nginx/sites-enabled/scanapi
  echo "XATO: nginx sozlamasi qabul qilinmadi, scanapi o'chirildi (argosacademy ta'sirlanmadi)"
  exit 1
fi
systemctl reload nginx

# 6) SSL: certbot (argosacademy.uz sertifikatini ham avtomatik yangilanadigan qiladi)
if ! command -v certbot >/dev/null; then
  apt-get update -qq && apt-get install -y -qq certbot python3-certbot-nginx >/dev/null
  echo "certbot: o'rnatildi"
fi
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
fi
systemctl enable --now certbot.timer >/dev/null 2>&1 || true
certbot renew --dry-run 2>&1 | grep -E "Congratulations|simulated renewals|failed" || true

# 7) Tekshiruv
for i in $(seq 1 20); do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4100/v1/health || true)
  [ "$code" = "200" ] && break; sleep 1
done
echo "health: $(curl -s http://127.0.0.1:4100/v1/health)"
echo "https:  $(curl -s -o /dev/null -w '%{http_code}' https://$DOMAIN/v1/health)"
systemctl is-active scan-api
