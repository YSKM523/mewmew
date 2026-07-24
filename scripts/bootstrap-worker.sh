#!/usr/bin/env bash
# One-time bootstrap for the mewmew API worker (run by the repo owner).
#
# Generates the app token, installs it plus the DeepSeek key as Worker secrets,
# and mirrors the app token to the GitHub repo so CI can bake it into the iOS
# build.
#
# The app token is a throttling key, not user authentication: it ships inside
# the app binary and is therefore extractable. Phase 6 replaces it with real
# user sessions. Rotate by re-running this script.
#
# Requires: gh (authenticated), npx/wrangler (Cloudflare login), openssl.

set -euo pipefail

APP_REPO="YSKM523/mewmew"
DEEPSEEK_ENV="$HOME/.config/geo-sampler/env"
worker_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../worker" && pwd)"

if [ ! -r "$DEEPSEEK_ENV" ]; then
  echo "error: cannot read $DEEPSEEK_ENV (expected DEEPSEEK_API_KEY there)" >&2
  exit 1
fi
# shellcheck disable=SC1090
set -a; . "$DEEPSEEK_ENV"; set +a
if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "error: DEEPSEEK_API_KEY is empty in $DEEPSEEK_ENV" >&2
  exit 1
fi

app_token="$(openssl rand -hex 24)"

cd "$worker_dir"
echo "==> Installing Worker secrets on mewmew-api"
printf '%s' "$app_token" | npx wrangler secret put APP_TOKEN
printf '%s' "$DEEPSEEK_API_KEY" | npx wrangler secret put DEEPSEEK_API_KEY

echo "==> Mirroring the app token to $APP_REPO for iOS builds"
printf '%s' "$app_token" | gh secret set MEWMEW_APP_TOKEN -R "$APP_REPO"

echo
echo "Done. Verify with:"
cat <<EOF
  curl -s -X POST https://mewmew-api.pp-account.workers.dev/v1/parse \\
    -H 'Content-Type: application/json' \\
    -H "X-Mewmew-Token: $app_token" \\
    -d '{"text":"明天早上八点吃药","tz":"America/Toronto","now":"2026-07-24T15:00:00"}'
EOF
