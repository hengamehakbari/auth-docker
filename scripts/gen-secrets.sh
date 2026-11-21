#!/usr/bin/env bash
# روی نود manager اجرا شود. Secretهای Swarm را می‌سازد (اگر وجود نداشته باشند).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${DOMAIN:?DOMAIN در .env تنظیم نشده}"

S=.secrets
mkdir -p "$S" && chmod 700 "$S"

[ -f $S/mongo_root_password ]       || openssl rand -hex 24 | tr -d '\n' > $S/mongo_root_password
[ -f $S/authentiq_admin_password ]  || openssl rand -hex 16 | tr -d '\n' > $S/authentiq_admin_password
[ -f $S/jwt_private.key ]           || openssl genrsa -out $S/jwt_private.key 2048
[ -f $S/jwt_public.key ]            || openssl rsa -in $S/jwt_private.key -pubout -out $S/jwt_public.key

# گواهی TLS: اگر گواهی واقعی دارید، قبل از اجرا در $S/tls.crt و $S/tls.key بگذارید
if [ ! -f $S/tls.crt ]; then
  echo ">> گواهی self-signed (فقط تست) برای *.${DOMAIN}"
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout $S/tls.key -out $S/tls.crt -subj "/CN=*.${DOMAIN}" \
    -addext "subjectAltName=DNS:*.${DOMAIN},DNS:${DOMAIN}"
fi
chmod 600 $S/*

create() {
  if docker secret inspect "$1" >/dev/null 2>&1; then echo "exists: $1"
  else docker secret create "$1" "$2" >/dev/null && echo "created: $1"; fi
}
create mongo_root_password      $S/mongo_root_password
create authentiq_admin_password $S/authentiq_admin_password
create jwt_private_key          $S/jwt_private.key
create jwt_public_key           $S/jwt_public.key
create tls_cert                 $S/tls.crt
create tls_key                  $S/tls.key
echo "رمز ادمین authentiq در $S/authentiq_admin_password است. پوشه‌ی $S را backup و از git دور نگه دارید."
