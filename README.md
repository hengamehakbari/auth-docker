# استقرار Authentiq + Account-Manager روی Docker Swarm (۲ سرور)

## معماری

- ۲ سرور لینوکس، هر دو **manager** در یک Swarm (`node1` و `node2`).
- `traefik:v2.11` به‌صورت **global** (یکی روی هر سرور)، پورت‌های 80/443 در حالت **host**.
- `authentiq` و `account-manager`: هرکدام ۲ replica با `max_replicas_per_node: 1` (یعنی روی هر سرور دقیقاً یک نسخه).
- `mongo` یک نمونه، روی نودی که برچسب `db=true` دارد.
- `visualizer` روی `visualizer.<DOMAIN>` و محدود به `ALLOWED_IPS`.
- پایش سلامت: `HEALTHCHECK` در Dockerfile (Swarm تسک ناسالم را می‌کُشد و جایگزین می‌کند) + healthcheck خود Traefik روی هر replica.

## پیش‌نیازها

1. روی هر دو سرور Docker Engine نصب باشد.
   - **هشدار:** Docker Engine 29 به بعد حداقل API 1.44 می‌خواهد و Traefik v2.11 با آن کار نمی‌کند
     (خطای `client version 1.24 is too old`). یا Docker 28.x نصب کنید، یا روی هر دو سرور در `/etc/docker/daemon.json`
     مقدار `{"min-api-version": "1.24"}` را بگذارید و Docker را restart کنید. visualizer هم همین مشکل را می‌تواند داشته باشد.
2. فایروال بین دو سرور: `2377/tcp`، `7946/tcp+udp`، `4789/udp` و **پروتکل ESP (IP protocol 50)** (برای overlay رمزنگاری‌شده).
3. از بیرون فقط `80` و `443` باز باشد.
4. DNS: رکورد A برای `auth.<DOMAIN>`، `account.<DOMAIN>` و `visualizer.<DOMAIN>` روی IP هر دو سرور.

## ۱) ساخت کلاستر

```bash
# node1
docker swarm init --advertise-addr <IP_NODE1>
docker swarm join-token manager      # خروجی را روی node2 اجرا کنید
# node2
docker swarm join --token <TOKEN> <IP_NODE1>:2377

# node1
docker node ls
docker node update --label-add db=true <نام-node1>
```

> با ۲ manager، از دست رفتن هر کدام باعث از دست رفتن quorum می‌شود: کانتینرهای در حال اجرا ادامه می‌دهند
> ولی تا برگشتن نود، Swarm نمی‌تواند چیزی را تغییر یا reschedule کند. برای HA واقعی یک نود سوم (manager سبک) اضافه کنید.

## ۲) تنظیمات و Secretها (روی node1)

```bash
cp .env.example .env      # DOMAIN, ALLOWED_IPS, OTHER_NODES=root@<IP_NODE2> و ... را پر کنید
./scripts/gen-secrets.sh  # رمزها، کلید JWT و گواهی TLS (self-signed برای تست)
```

برای گواهی واقعی، قبل از اجرای اسکریپت فایل‌های `.secrets/tls.crt` و `.secrets/tls.key` (wildcard) را بگذارید.
(Let's Encrypt عمداً استفاده نشده: ذخیره‌ی `acme.json` بین دو Traefik مشترک نیست.)

## ۳) Deploy

```bash
./scripts/deploy.sh
docker stack services app
docker service ps app_authentiq app_account-manager   # باید هر کدام یک تسک روی هر نود باشد
```

## ۴) صحت‌سنجی

```bash
# با DNS واقعی:
curl -k https://auth.example.com/authentiq/v1/heartbeat
curl -k https://account.example.com/accountico/heartbeat
# بدون DNS (تست مستقیم روی هر سرور):
curl -k --resolve auth.example.com:443:<IP_NODE2> https://auth.example.com/authentiq/v1/heartbeat
# visualizer: از IP مجاز 200، از IP غیرمجاز 403
curl -k -o /dev/null -w "%{http_code}\n" https://visualizer.example.com/
```

تست خودترمیمی:

```bash
docker kill $(docker ps -q -f name=app_authentiq)   # Swarm تسک جدید می‌سازد
docker node update --availability drain <node2>     # replicaها نیاز به نود دیگر دارند (max 1 per node → pending)
docker node update --availability active <node2>
```

## توسعه

```bash
docker compose up --build    # nodemon + bind mount، auth روی :2052 و account روی :5000
```

## محدودیت‌های شناخته‌شده

- **MongoDB تک‌نمونه است** (SPOF). اگر نود دارای برچسب `db` از دست برود، هر دو سرویس از کار می‌افتند.
  راه‌حل: replica set با ۳ عضو (و تغییر connection string در کد، چون `replicaSet` ندارد).
- `mongo:4.4` برای سازگاری با `mongoose@5` / `mongodb@3` انتخاب شده و EOL است.
- Traefik و visualizer به `docker.sock` دسترسی دارند (فقط روی managerها). برای سخت‌تر کردن، `docker-socket-proxy` بگذارید.
- Secretهای Swarm تغییرناپذیرند؛ برای تغییر باید secret جدید با نام جدید ساخت و stack را به‌روزرسانی کرد.
- اگر جلوی سرورها load balancer ابری باشد، IP کلاینت برای `ipWhiteList` از دست می‌رود (نیاز به PROXY protocol / `forwardedHeaders.trustedIPs`).

================================================================================

project/                          ← پوشه‌ی اصلی (مثلاً ~/project روی node1)
├── docker-compose.yml            ← توسعه
├── docker-stack.yml              ← استقرار روی Swarm
├── .env                          ← کپی از .env.example (خودتان می‌سازید)
├── .env.example
├── README.md
├── traefik/
│   └── dynamic.yml
├── scripts/
│   ├── gen-secrets.sh
│   └── deploy.sh
├── .secrets/                     ← gen-secrets.sh خودش می‌سازد (از git دور نگه دارید)
│
├── auth/                         ← محتوای auth.zip (سورس اصلی سرویس)
│   ├── bin/  config/  src/  package.json  package-lock.json ...
│   ├── Dockerfile                ← فایل جدید
│   ├── .dockerignore             ← فایل جدید
│   └── docker-entrypoint.sh      ← فایل جدید
│
└── account-manager/              ← محتوای account-manager.zip (سورس اصلی)
    ├── server.js  app.js  api/  package.json  package-lock.json ...
    ├── Dockerfile                ← فایل جدید
    ├── .dockerignore             ← فایل جدید
    └── docker-entrypoint.sh      ← فایل جدید
