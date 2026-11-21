#!/bin/sh
# هر متغیر VAR_FILE=/path را به VAR=<محتوای فایل> تبدیل می‌کند (برای Docker secrets)
set -e
for f in $(env | grep -E '^[A-Z0-9_]+_FILE=' | cut -d= -f1); do
  eval "path=\${$f}"
  if [ ! -r "$path" ]; then
    echo "entrypoint: secret file not readable: $path" >&2
    exit 1
  fi
  export "${f%_FILE}=$(cat "$path")"
  unset "$f"
done
exec "$@"
