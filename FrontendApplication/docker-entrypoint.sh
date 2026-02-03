#!/bin/sh
set -eu

TEMPLATE="/etc/nginx/templates/config.js.tmpl"
TARGET="/var/www/config.js"

if [ -f "$TEMPLATE" ]; then
  API_GATEWAY_VALUE="${API_GATEWAY:-}"
  ESCAPED_API_GATEWAY=$(printf '%s' "$API_GATEWAY_VALUE" | sed 's/[&|]/\\&/g')
  sed "s|__API_GATEWAY__|$ESCAPED_API_GATEWAY|g" "$TEMPLATE" > "$TARGET"
fi

exec "$@"
