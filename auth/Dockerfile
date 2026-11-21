FROM node:20-alpine AS base
WORKDIR /app
COPY package.json package-lock.json ./

# ---- dev: با nodemon و bind mount سورس (docker-compose.yml) ----
FROM base AS dev
ENV NODE_ENV=development
RUN npm ci
COPY . .
EXPOSE 2052
CMD ["npm", "run", "dev"]

# ---- prod: ایمیج نهایی برای Swarm ----
FROM base AS prod
ENV NODE_ENV=production
RUN npm ci --omit=dev && npm cache clean --force
COPY --chown=node:node bin ./bin
COPY --chown=node:node config ./config
COPY --chown=node:node src ./src
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
USER node
EXPOSE 2052
# سرور فقط بعد از اتصال به DB شروع به listen می‌کند، پس heartbeat سالم = اپ + DB سالم
HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${AUTHENTIQ_PORT:-2052}/authentiq/v1/heartbeat" >/dev/null || exit 1
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "./bin/www"]
