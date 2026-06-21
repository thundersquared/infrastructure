#!/bin/sh
# Monit chat notifier. Managed by Ansible (system/monit role).
#
# Sends a message to Telegram and/or Slack, depending on which credentials
# are present in /etc/monit/notify-chat.env. Any unconfigured channel is a
# silent no-op. This script must never fail in a way that blocks monit, so it
# always exits 0.
#
# Usage: notify-chat.sh "message text"

set -u

ENV_FILE="/etc/monit/notify-chat.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

MESSAGE="${1:-monit alert}"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
TEXT="[$HOSTNAME] $MESSAGE"

# --- Telegram ---------------------------------------------------------------
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  curl -fsS --max-time 15 \
    -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${TEXT}" \
    >/dev/null 2>&1 || true
fi

# --- Slack ------------------------------------------------------------------
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  # Escape double quotes and backslashes for safe JSON embedding.
  ESCAPED=$(printf '%s' "$TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')
  curl -fsS --max-time 15 \
    -H 'Content-Type: application/json' \
    -X POST \
    --data "{\"text\":\"${ESCAPED}\"}" \
    "$SLACK_WEBHOOK_URL" \
    >/dev/null 2>&1 || true
fi

exit 0
