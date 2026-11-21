#!/usr/bin/env bash
# روی نود manager: build ایمیج‌ها، رساندن به همه‌ی نودها، deploy استک
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${DOMAIN:?}" "${ALLOWED_IPS:?}" "${TAG:?}" "${MONGO_USERNAME:?}" "${AUTHENTIQ_ADMIN_USERNAME:?}"
REGISTRY_PREFIX="${REGISTRY_PREFIX:-}"; export REGISTRY_PREFIX

IMAGES=("${REGISTRY_PREFIX}authentiq:${TAG}" "${REGISTRY_PREFIX}account-manager:${TAG}")
docker build --target prod -t "${IMAGES[0]}" ./auth
docker build --target prod -t "${IMAGES[1]}" ./account-manager

if [ -n "$REGISTRY_PREFIX" ]; then
  for i in "${IMAGES[@]}"; do docker push "$i"; done
  RESOLVE=always
else
  : "${OTHER_NODES:?بدون registry باید OTHER_NODES (مثلاً root@10.0.0.2) را تنظیم کنید}"
  for n in $OTHER_NODES; do docker save "${IMAGES[@]}" | ssh "$n" docker load; done
  RESOLVE=never
fi

docker stack deploy --with-registry-auth --resolve-image "$RESOLVE" -c docker-stack.yml app
echo "وضعیت: docker stack services app"
