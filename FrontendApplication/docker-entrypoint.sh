#!/bin/sh
set -eu

# Define template and target for Nginx config
NGINX_TEMPLATE="/etc/nginx/templates/vhost.conf.tmpl"
NGINX_TARGET="/etc/nginx/conf.d/default.conf"

# Define template and target for Frontend JS config
JS_TEMPLATE="/etc/nginx/templates/config.js.tmpl"
JS_TARGET="/var/www/config.js"

# Get the API Gateway endpoint from the environment variable provided by App Design Center
# Use a fallback for local development if needed
API_ENDPOINT="${api_service_SERVICE_ENDPOINT:-http://api:3000}"

# Create Nginx config from template
# This replaces the __API_ENDPOINT__ placeholder with the actual service URL
if [ -f "$NGINX_TEMPLATE" ]; then
  sed "s|__API_ENDPOINT__|$API_ENDPOINT|g" "$NGINX_TEMPLATE" > "$NGINX_TARGET"
fi

# Create Frontend JS config from template
# This step is now less critical if Nginx handles the proxy, but we keep it for consistency.
# It makes the frontend aware of the relative path to the API.
if [ -f "$JS_TEMPLATE" ]; then
  # The frontend just needs to know to call the relative /api/ path.
  # The API_GATEWAY variable in JS will be an empty string, causing it to use the current origin.
  sed "s|__API_GATEWAY__|""|g" "$JS_TEMPLATE" > "$JS_TARGET"
fi

# Execute the original CMD from the Dockerfile (starts Nginx)
exec "$@"
