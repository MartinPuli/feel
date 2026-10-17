#!/bin/sh
# Copy SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY from an env file (default: chalk/.env)
# into the git-ignored ios/Config/Supabase.local.xcconfig, then rebuild the app.
set -eu
cd "$(dirname "$0")/.."
env_file="${1:-../chalk/.env}"
[ -f "$env_file" ] || { echo "No $env_file. Pass the env file path." >&2; exit 2; }
read_value() { sed -n "s/^$1=//p" "$env_file" | tail -n 1 | tr -d '\r' | sed -e 's/^["'\'']//' -e 's/["'\'']$//'; }
url=$(read_value SUPABASE_URL); key=$(read_value SUPABASE_PUBLISHABLE_KEY)
url=${url%/}
case "$url" in https://?*) ;; *) echo 'Set SUPABASE_URL to https://<project>.supabase.co' >&2; exit 2;; esac
[ -n "$key" ] || { echo 'Set SUPABASE_PUBLISHABLE_KEY.' >&2; exit 2; }
case "$key" in sb_secret_*) echo 'Use the publishable (anon) key, never the secret key.' >&2; exit 2;; esac
# xcconfig treats // as a comment, so split it with an empty substitution.
printf 'SUPABASE_URL = https:/$()/%s\nSUPABASE_PUBLISHABLE_KEY = %s\n' "${url#https://}" "$key" > Config/Supabase.local.xcconfig
echo 'Wrote ios/Config/Supabase.local.xcconfig. Rebuild the Lantern app.'
