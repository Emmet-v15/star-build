#!/usr/bin/env bash
# star's private Git dependencies (v15-notify, v15-kit) are fetched using
# this builder's own read-only deploy keys (secrets NOTIFY_KEY, KIT_KEY: one
# key per repository and builder). Each key has its own SSH host alias, and
# the repository's HTTPS URL points to it, so Cargo fetches the dependencies
# exactly as named in Cargo.toml, leaving Cargo.lock unchanged. Before any
# of star's code runs (build scripts, npm install scripts), the keys,
# aliases, and URLs are removed.
#   deps.sh <path to src-tauri/Cargo.toml>
set -euo pipefail
manifest="${1:?usage: deps.sh <Cargo.toml>}"
keys="$RUNNER_TEMP/keys"

forget() {
  rm -rf "$keys" ~/.ssh/config
  git config --global --get-regexp '^url\.' | sed -E 's/\.insteadof .*//I' | sort -u | while read -r s; do
    git config --global --remove-section "$s"
  done
}
trap forget EXIT

add() {
  local repo="$1" key="$2"
  [ -n "$key" ] || { echo "no key for $repo (its secret in Emmet-v15/star-build)"; exit 1; }
  mkdir -p "$keys" ~/.ssh
  printf '%s\n' "$key" > "$keys/$repo"
  chmod 600 "$keys/$repo"
  cat >> ~/.ssh/config <<CFG
Host gh-$repo
  HostName github.com
  User git
  IdentityFile $keys/$repo
  IdentitiesOnly yes
CFG
  git config --global "url.git@gh-$repo:Emmet-v15/$repo.insteadOf" "https://github.com/Emmet-v15/$repo"
}

mkdir -p ~/.ssh
grep -q '^github.com ' ~/.ssh/known_hosts 2>/dev/null \
  || curl -fsS https://api.github.com/meta | jq -r '.ssh_keys[] | "github.com " + .' | tr -d '\r' >> ~/.ssh/known_hosts
add v15-notify "$NOTIFY_KEY"
add v15-kit "$KIT_KEY"
unset NOTIFY_KEY KIT_KEY
cargo fetch --locked --manifest-path "$manifest" > "$RUNNER_TEMP/fetch.log" 2>&1 \
  || { grep -E "error|failed|denied" "$RUNNER_TEMP/fetch.log" | head -20; exit 1; }
echo "private dependencies fetched: $(ls ~/.cargo/git/checkouts 2>/dev/null | sed -E 's/-[0-9a-f]+$//' | xargs)"
