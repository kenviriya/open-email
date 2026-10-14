#!/usr/bin/env sh
# Installs or updates Open Email in $OPEN_EMAIL_DIR (default ./open-email).
#   curl -fsSL https://github.com/kenviriya/open-email/releases/latest/download/install.sh | bash
# Re-running keeps existing secrets in .env and moves the install to this script's version.
set -eu

REPO=kenviriya/open-email
# Replaced with the release tag by .github/workflows/release.yml.
VERSION="${OPEN_EMAIL_VERSION:-@VERSION@}"
DIR="${OPEN_EMAIL_DIR:-$PWD/open-email}"

die() { echo "Error: $*" >&2; exit 1; }
# stdin is the script itself when piped from curl, so prompts read from the terminal.
ask() {
  { : </dev/tty; } 2>/dev/null || die "no terminal for prompts. Create $DIR/.env from .env.example and re-run."
  printf "%s" "$1" >/dev/tty
  read -r REPLY </dev/tty
}

main() {
  case "$VERSION" in @*) die "unknown version. Install from a release, or set OPEN_EMAIL_VERSION=vX.Y.Z." ;; esac
  for cmd in curl docker openssl; do
    command -v "$cmd" >/dev/null || die "$cmd is required. Docker: https://docs.docker.com/engine/install/"
  done
  docker compose version >/dev/null 2>&1 || die "the Docker Compose plugin is required: https://docs.docker.com/compose/install/linux/"
  docker info >/dev/null 2>&1 || die "cannot reach Docker. Run as root or add your user to the docker group."

  mkdir -p "$DIR/deploy"
  cd "$DIR"
  echo "Installing Open Email $VERSION into $DIR"
  for f in docker-compose.yml deploy/Caddyfile .env.example; do
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$VERSION/$f" -o "$f.tmp" || die "could not download $f for $VERSION."
    mv "$f.tmp" "$f"
  done

  if [ ! -f .env ]; then
    ask "Public hostname for Open Email (e.g. mail.acme.com): "
    DOMAIN=$REPLY
    [ -n "$DOMAIN" ] || die "hostname is required."
    ask "HTTPS mode: [1] Caddy on this server (ports 80/443)  [2] Cloudflare Tunnel  [3] My own proxy: "
    PROFILE=""; TUNNEL=""; BIND="127.0.0.1:3000"
    case "$REPLY" in
      1|"") PROFILE=caddy ;;
      2) PROFILE=tunnel
         ask "Cloudflare Tunnel token (route $DOMAIN to http://web:3000): "
         TUNNEL=$REPLY ;;
      3) BIND="0.0.0.0:3000" ;;
      *) die "unknown choice." ;;
    esac
    (umask 077; cat > .env <<EOF
OPEN_EMAIL_VERSION=$VERSION
DOMAIN=$DOMAIN
PUBLIC_URL=https://$DOMAIN
COMPOSE_PROFILES=$PROFILE
CLOUDFLARE_TUNNEL_TOKEN=$TUNNEL
WEB_BIND=$BIND
POSTGRES_PASSWORD=$(openssl rand -hex 24)
APP_SECRET=$(openssl rand -base64 32)
EOF
)
    echo "Wrote $DIR/.env. Back up APP_SECRET: without it, saved Resend and R2 keys must be re-entered."
  elif grep -q '^OPEN_EMAIL_VERSION=' .env; then
    sed -i "s/^OPEN_EMAIL_VERSION=.*/OPEN_EMAIL_VERSION=$VERSION/" .env
  else
    echo "OPEN_EMAIL_VERSION=$VERSION" >> .env
  fi

  docker compose pull
  docker compose up -d --remove-orphans
  PUBLIC_URL=$(sed -n 's/^PUBLIC_URL=//p' .env)
  echo "Open Email $VERSION is running. Open $PUBLIC_URL to finish setup."
}

# Runs only once the whole script has downloaded, so a cut-off download does nothing.
main "$@"
