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
# Validate optional settings into a temporary file; a failed setup preserves the previous build configuration.
config_file=$(mktemp Config/Supabase.local.xcconfig.XXXXXX)
trap 'rm -f "$config_file"' EXIT HUP INT TERM
# xcconfig treats // as a comment, so split it with an empty substitution.
printf 'SUPABASE_URL = https:/$()/%s\nSUPABASE_PUBLISHABLE_KEY = %s\n' "${url#https://}" "$key" > "$config_file"
# Optional: the voice token service, so the assistant is configured on first launch without typing the code.
voice_url=$(read_value FEEL_VOICE_ENDPOINT); voice_token=$(read_value FEEL_VOICE_ACCESS_TOKEN)
voice_mode=$(read_value FEEL_VOICE_AUTH_MODE)
voice_mode=${voice_mode:-demo}
case "$voice_mode" in demo|supabase) ;; *) echo 'FEEL_VOICE_AUTH_MODE must be demo or supabase.' >&2; exit 2;; esac
if [ "$voice_mode" = supabase ] || [ -n "$voice_url" ]; then
  case "$voice_url" in https://?*) ;; *) echo 'Set FEEL_VOICE_ENDPOINT to https://<host>/session' >&2; exit 2;; esac
  printf 'FEEL_VOICE_ENDPOINT = https:/$()/%s\nFEEL_VOICE_AUTH_MODE = %s\n' "${voice_url#https://}" "$voice_mode" >> "$config_file"
  if [ "$voice_mode" = demo ]; then
    [ -n "$voice_token" ] || { echo 'Demo voice requires its separate service access code.' >&2; exit 2; }
    case "$voice_token" in sk-*|grok_*|xai-*) echo 'Use the demo service access code, never a provider key.' >&2; exit 2;; esac
    printf 'FEEL_VOICE_ACCESS_TOKEN = %s\n' "$voice_token" >> "$config_file"
  fi
  echo 'Voice endpoint included. Supabase mode uses the signed-in account and excludes the demo access code.'
fi
# Optional: the Chalk gateway (restricted router key), so Where-is and describe_ahead work on first launch.
chalk_key=$(read_value CHALK_ROUTER_API_KEY); chalk_env=$(read_value CHALK_ENV_ID); chalk_model=$(read_value FEEL_CHALK_MODEL); chalk_host=$(read_value CHALK_API_HOST)
if [ -n "$chalk_key" ] && [ -n "$chalk_env" ]; then
  case "$chalk_key" in sk-*) echo 'CHALK_ROUTER_API_KEY must be the Chalk gateway key, never a provider key.' >&2; exit 2;; esac
  printf 'FEEL_CHALK_KEY = %s\nFEEL_CHALK_ENV = %s\n' "$chalk_key" "$chalk_env" >> "$config_file"
  [ -n "$chalk_model" ] && printf 'FEEL_CHALK_MODEL = %s\n' "$chalk_model" >> "$config_file"
  [ -n "$chalk_host" ] && printf 'FEEL_CHALK_HOST = https:/$()/%s\n' "${chalk_host#https://}" >> "$config_file"
  echo 'Chalk gateway included.'
fi
# Optional authenticated context proxy. No Chalk service credentials belong on the phone.
context_url=$(read_value FEEL_CONTEXT_URL)
if [ -n "$context_url" ]; then
  case "$context_url" in https://?*/api/context|https://?*/context) ;; *) echo 'Set FEEL_CONTEXT_URL to the HTTPS context endpoint.' >&2; exit 2;; esac
  printf 'FEEL_CONTEXT_URL = https:/$()/%s\n' "${context_url#https://}" >> "$config_file"
  echo 'Authenticated context endpoint included; reads still require opt-in and sign-in.'
fi
mv "$config_file" Config/Supabase.local.xcconfig
echo 'Wrote ios/Config/Supabase.local.xcconfig. Rebuild the Lantern app.'
