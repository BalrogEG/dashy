FROM node:24-alpine AS build
WORKDIR /app
COPY package.json yarn.lock ./
# Guard: newer Node images may no longer bundle yarn v1.
RUN command -v yarn >/dev/null || npm install -g yarn@1.22.22
# Pass the sandbox proxy to yarn v1 explicitly (HTTP_PROXY/HTTPS_PROXY are predefined build args).
RUN yarn install --frozen-lockfile --network-timeout 600000 ${HTTPS_PROXY:+--https-proxy "$HTTPS_PROXY" --proxy "$HTTP_PROXY"}
COPY . .
RUN yarn build

FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json yarn.lock ./
# Guard: newer Node images may no longer bundle yarn v1.
RUN command -v yarn >/dev/null || npm install -g yarn@1.22.22
RUN yarn install --production --frozen-lockfile --network-timeout 600000 ${HTTPS_PROXY:+--https-proxy "$HTTPS_PROXY" --proxy "$HTTP_PROXY"} \
  && yarn cache clean

FROM node:24-alpine
ENV NODE_ENV=production \
    IS_DOCKER=true \
    PORT=3000 \
    HOST=0.0.0.0
WORKDIR /app
# Upstream also installs ping and setcap's it for ICMP status checks; dropped here because
# AiX runs containers with --cap-drop=ALL + no-new-privileges (HTTP status checks still work).
RUN apk add --no-cache tzdata tini \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
COPY --from=deps  /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/public ./public
COPY --from=build /app/services ./services
COPY --from=build /app/src/utils/config/ConfigSchema.json ./src/utils/config/ConfigSchema.json
COPY --from=build /app/server.js ./server.js
COPY --from=build /app/package.json ./package.json
COPY --chown=node:node --from=build /app/user-data/conf.yml ./user-data/conf.yml
USER 1000:1000
EXPOSE 3000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
