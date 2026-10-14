# Open Email

Self-hosted business email built on [Resend](https://resend.com) and Cloudflare R2. Run it on your own server, paste your Resend API key and R2 credentials into the setup wizard, and you can send and receive mail.

- Rich text editor, attachments, inline images, reply/forward threading
- Multiple users, each with their own mailboxes; shared mailboxes such as `sales@`
- Desktop three-pane layout and a mobile layout
- Go (Fiber, GORM) API and worker, Next.js + shadcn/ui, Postgres, Redis

## Requirements

- A Linux server with [Docker Engine and the Compose plugin](https://docs.docker.com/engine/install/), plus `curl` and `openssl`
- A [Resend](https://resend.com) account and a **Full access** API key
- A [Cloudflare R2](https://developers.cloudflare.com/r2/) bucket
- A domain you control, and a hostname for the app (e.g. `mail.acme.com`) reachable over public HTTPS so Resend can deliver webhooks

## Install

```sh
curl -fsSL https://github.com/kenviriya/open-email/releases/latest/download/install.sh | bash
```

This creates `./open-email` (set `OPEN_EMAIL_DIR` to choose another folder), downloads `docker-compose.yml` and the Caddy config for the latest release, asks two questions, writes `.env` (with a generated database password and `APP_SECRET`) and starts the stack. Prefer to read the script first? Download it, review it, then run `bash install.sh`.

1. **Public hostname**, e.g. `mail.acme.com`
2. **How to provide HTTPS** (see below)

When it finishes, open `https://<your hostname>` and complete the setup wizard.

### HTTPS options

| Mode | Use when | You provide |
|---|---|---|
| 1. Caddy | The server has ports 80 and 443 open to the internet | A DNS A/AAAA record for the hostname pointing to the server |
| 2. Cloudflare Tunnel | Home server, NAT, or no open ports | A tunnel token |
| 3. Own proxy | You already run nginx, Traefik, etc. | A proxy from your hostname to port 3000 |

**Caddy.** Create the DNS record before running the installer. Caddy gets a Let's Encrypt certificate on first start; check `docker compose logs caddy` if the site does not load.

**Cloudflare Tunnel.** In Cloudflare Zero Trust → Networks → Tunnels, create a tunnel, copy its token, and add a public hostname (your app hostname) with service `http://web:3000`. Paste the token when the installer asks.

**Own proxy.** The web app listens on `0.0.0.0:3000`. If your proxy runs on the same host, set `WEB_BIND=127.0.0.1:3000` in `.env` so port 3000 is not exposed, otherwise firewall it. Disable response buffering so live updates (`/api/events`, server-sent events) work. nginx example:

```nginx
server {
    listen 443 ssl;
    server_name mail.acme.com;
    # ssl_certificate ... ;
    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 1h;
    }
}
```

## Setup wizard

1. **Admin account.** Password of at least 12 characters.
2. **Resend API key.** Must be **Full access**; sending-only keys cannot read inbound mail or create webhooks.
3. **Domain.** If the domain already receives mail elsewhere (Google Workspace, Microsoft 365, ...), the wizard warns you and recommends a subdomain such as `mail.acme.com` so your existing mail keeps working. Add the DNS records shown at your DNS provider and click **Re-check** until they verify (DNS can take a few minutes).
4. **Cloudflare R2.** In the Cloudflare dashboard go to R2 object storage → Overview → Account Details → Manage (API Tokens) → Create Account API token, with permission **Object Read & Write** scoped to your Open Email bucket only.
   The wizard writes, reads, inspects and deletes a test object, and **rejects Admin tokens** (any token that can list all buckets). It cannot tell a token scoped to one bucket from an Object Read & Write token scoped to all buckets, so scope it yourself.
5. **Finish.** Creates the Resend webhook and sends a test email. If the webhook cannot reach your server, inbound mail is still collected every 5 minutes.

After setup, add users and shared mailboxes from the admin pages. Resend and R2 keys can be replaced later under admin integrations.

## Configuration

All settings live in `open-email/.env`, created by the installer. Run `docker compose` commands from that folder. See [.env.example](.env.example) to write it by hand.

| Variable | Purpose |
|---|---|
| `OPEN_EMAIL_VERSION` | Release tag of the app images, set by the installer |
| `DOMAIN` | Public hostname of the app |
| `PUBLIC_URL` | `https://<DOMAIN>`; used for webhooks, cookies and origin checks |
| `COMPOSE_PROFILES` | `caddy`, `tunnel`, or empty for your own proxy |
| `CLOUDFLARE_TUNNEL_TOKEN` | Tunnel token (tunnel mode only) |
| `WEB_BIND` | Host address for the web app port, e.g. `127.0.0.1:3000` |
| `POSTGRES_PASSWORD` | Database password, generated on install |
| `APP_SECRET` | 32 random bytes (base64); encrypts the saved Resend and R2 keys |
| `RESEND_RPS` | Resend requests per second (default `10`) |

Apply changes with `docker compose up -d`.

## Operating

```sh
docker compose ps                 # status
docker compose logs -f app worker # API and worker logs
docker compose down               # stop (data volumes are kept)
docker compose up -d              # start
```

### Updating

Back up first, then re-run the installer from the folder that contains `open-email/`. It keeps your `.env` and moves you to the latest release:

```sh
curl -fsSL https://github.com/kenviriya/open-email/releases/latest/download/install.sh | bash
```

To install a specific release, use `https://github.com/kenviriya/open-email/releases/download/vX.Y.Z/install.sh`.

### Backups

Back up three things:

1. **Postgres** (users, mailboxes, message index):
   ```sh
   docker compose exec -T postgres pg_dump -U openemail openemail | gzip > openemail-$(date +%F).sql.gz
   ```
2. **Your R2 bucket** (message bodies and attachments), e.g. with [rclone](https://rclone.org/s3/#cloudflare-r2) or R2 bucket replication.
3. **`.env`**, especially `APP_SECRET`. Losing it keeps your mail intact, but you must re-enter the Resend and R2 keys.

Restore Postgres into a fresh install (before running the wizard):

```sh
docker compose up -d postgres
gunzip -c openemail-YYYY-MM-DD.sql.gz | docker compose exec -T postgres psql -U openemail openemail
docker compose up -d
```

## Limits

- Resend accepts at most 40 MB per email **after Base64 encoding**, so about 29 MB of attachments. The composer blocks files over the limit before upload, and the API checks again.
- Resend allows 10 API requests per second per team by default. Open Email shares one limiter across the API and worker, and sending takes priority over processing inbound mail. Use a dedicated Resend team if other apps share the key.

## Troubleshooting

- **Site does not load (Caddy):** check that the DNS record points to the server and ports 80/443 are open, then `docker compose logs caddy`.
- **Site does not load (Tunnel):** check that the tunnel's public hostname points to `http://web:3000`, then `docker compose logs tunnel`.
- **Inbound mail arrives late:** Resend cannot reach your webhook, so mail is only collected by the 5-minute poll. Make sure `PUBLIC_URL` is reachable from the internet.
- **"Sending-only" key error:** create a new Resend key with Full access.
- **R2 "token too broad":** you used an Admin token. Create an Object Read & Write token scoped to the bucket.
- **Live updates not appearing (own proxy):** disable response buffering for `/api/events`.

## Development

The application source is not in this repository. This repository holds the installer, the Docker Compose stack and the API contract. For local dependencies: `docker compose -f docker-compose.dev.yml up -d` (Postgres, Redis, MinIO).

API contract: [docs/API.md](docs/API.md).
