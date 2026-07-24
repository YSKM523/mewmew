#!/usr/bin/env bash
# One-time bootstrap for mewmew CI code signing (run by the repo owner).
#
# Creates an SSH deploy key scoped to the mewmew-certs repo, generates the
# fastlane match encryption password, and stores both as secrets on the mewmew
# repo. Local key material is wiped on exit.
#
# Requires: gh (authenticated), ssh-keygen, openssl.
# Safe to re-run: it replaces the deploy key and rotates the match password.
# NOTE: rotating MATCH_PASSWORD after certificates exist makes the existing
# encrypted certs unreadable — if that happens, empty the mewmew-certs repo and
# let the next CI run recreate them.

set -euo pipefail

APP_REPO="YSKM523/mewmew"
CERTS_REPO="YSKM523/mewmew-certs"
KEY_TITLE="mewmew-ci-match"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

echo "==> Generating deploy keypair (ed25519)"
ssh-keygen -t ed25519 -C "$KEY_TITLE" -f match_key -N "" -q

echo "==> Removing any previous '$KEY_TITLE' deploy key on $CERTS_REPO"
gh api "repos/$CERTS_REPO/keys" --jq '.[] | select(.title=="'"$KEY_TITLE"'") | .id' \
  | while read -r id; do gh api -X DELETE "repos/$CERTS_REPO/keys/$id" --silent; done

echo "==> Adding deploy key (write access) to $CERTS_REPO"
# gh 2.4 has no `gh repo deploy-key`; go through the API directly.
gh api "repos/$CERTS_REPO/keys" \
  -f title="$KEY_TITLE" \
  -f key="$(cat match_key.pub)" \
  -F read_only=false \
  --jq '"deploy key id: \(.id)"'

echo "==> Storing secrets on $APP_REPO"
gh secret set MATCH_DEPLOY_KEY -R "$APP_REPO" < match_key
openssl rand -base64 24 | tr -d '\n' | gh secret set MATCH_PASSWORD -R "$APP_REPO"

echo
echo "Done. Secrets on $APP_REPO:"
gh secret list -R "$APP_REPO"
echo
echo "Next: trigger the TestFlight build with"
echo "  gh workflow run iOS -R $APP_REPO"
