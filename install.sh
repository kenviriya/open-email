#!/usr/bin/env sh
# Creates .env once and starts Open Email. Re-running keeps existing secrets.
set -eu
cd "$(dirname "$0")"

command -v docker >/dev/null || { echo "Docker is required: https://docs.docker.com/engine/install/"; exit 1; }

if [ ! -f .env ]; then
  printf "Public hostname for Open Email (e.g. mail.acme.com): "
  read -r DOMAIN
  [ -n "$DOMAIN" ] || { echo "Hostname is required."; exit 1; }
  printf "HTTPS mode: [1] Caddy on this server (ports 80/443)  [2] Cloudflare Tunnel  [3] My own proxy: "
  read -r MODE
  PROFILE=""; TUNNEL=""; BIND="127.0.0.1:3000"
  case "$MODE" in
    1|"") PROFILE=caddy ;;
    2) PROFILE=tunnel
       printf "Cloudflare Tunnel token (route %s to http://web:3000): " "$DOMAIN"
       read -r TUNNEL ;;
    3) BIND="0.0.0.0:3000" ;;
    *) echo "Unknown choice."; exit 1 ;;
  esac
  umask 077
  cat > .env <<EOF
DOMAIN=$DOMAIN
PUBLIC_URL=https://$DOMAIN
COMPOSE_PROFILES=$PROFILE
CLOUDFLARE_TUNNEL_TOKEN=$TUNNEL
WEB_BIND=$BIND
POSTGRES_PASSWORD=$(openssl rand -hex 24)
APP_SECRET=$(openssl rand -base64 32)
EOF
  echo "Wrote .env. Back up APP_SECRET: without it, saved Resend and R2 keys must be re-entered."
fi

docker compose up -d --build
. ./.env
echo "Open $PUBLIC_URL to finish setup."
