# Imagen del cliente web de CircleGuard (Expo / React Native Web)
#   Etapa 1: compila la app a archivos estáticos con `expo export -p web`
#   Etapa 2: los sirve con nginx sin privilegios (usuario no root, puerto 8080)
# Uso: docker build --build-arg APP_VERSION=1.0.42 -t circleguard/web:1.0.42 mobile

FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
ARG APP_VERSION=dev
RUN CI=1 npx expo export -p web --output-dir dist \
 && echo "${APP_VERSION}" > dist/version.txt

FROM nginxinc/nginx-unprivileged:1.27-alpine
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="circleguard-web" \
      org.opencontainers.image.version="${APP_VERSION}"
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=6 \
  CMD wget -qO- http://127.0.0.1:8080/health > /dev/null || exit 1
