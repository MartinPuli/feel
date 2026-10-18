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
# Optional: the voice token service, so the assistant is configured on first launch without typing the code.
voice_url=$(read_value FEEL_VOICE_ENDPOINT); voice_token=$(read_value FEEL_VOICE_ACCESS_TOKEN)
if [ -n "$voice_url" ] && [ -n "$voice_token" ]; then
  case "$voice_url" in https://?*) ;; *) echo 'Set FEEL_VOICE_ENDPOINT to https://<host>/session' >&2; exit 2;; esac
  case "$voice_token" in sk-*) echo 'FEEL_VOICE_ACCESS_TOKEN must be the service access code, never an OpenAI key.' >&2; exit 2;; esac
  printf 'FEEL_VOICE_ENDPOINT = https:/$()/%s\nFEEL_VOICE_ACCESS_TOKEN = %s\n' "${voice_url#https://}" "$voice_token" >> Config/Supabase.local.xcconfig
  echo 'Voice service included.'
fi
echo 'Wrote ios/Config/Supabase.local.xcconfig. Rebuild the Lantern app.'
