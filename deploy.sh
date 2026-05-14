#!/usr/bin/env bash
# deploy.sh — Blue-Green deployment script
# Usage: bash deploy.sh
# Requires: docker, docker compose, curl, sed (all available in Git Bash on Windows).

set -euo pipefail

HEALTH_RETRIES=10
HEALTH_INTERVAL=3

# ── Detect current active slot from running nginx container ──────────────────
if docker inspect nginx &>/dev/null; then
    CURRENT=$(docker exec nginx grep -oE "app-(blue|green)" /etc/nginx/nginx.conf 2>/dev/null \
              | head -1 | sed 's/app-//' || echo "")
    FIRST_DEPLOY=false
else
    CURRENT=""
    FIRST_DEPLOY=true
fi

# ── Determine target slot ────────────────────────────────────────────────────
# First deploy or green→blue rotation → blue; blue→green rotation → green
if [[ "$CURRENT" == "blue" ]]; then
    NEW="green"
    NEW_PORT=8002
else
    NEW="blue"
    NEW_PORT=8001
fi

echo "Current active slot : ${CURRENT:-none} (first deploy: $FIRST_DEPLOY)"
echo "Deploying to        : $NEW (port $NEW_PORT)"

# ── First deploy: generate nginx config and bring the full stack up ──────────
if [[ "$FIRST_DEPLOY" == "true" ]]; then
    echo "First deploy: generating nginx config and starting stack..."
    sed "s/{{ACTIVE_HOST}}/app-$NEW/g" nginx/nginx.conf.template > nginx/nginx.conf
    docker compose up -d
else
    # Subsequent deploy: only recreate the inactive slot
    echo "Updating app-$NEW with the latest image..."
    docker compose up -d --no-deps --force-recreate "app-$NEW"
fi

# ── Health check loop ────────────────────────────────────────────────────────
echo "Waiting for app-$NEW to pass health check..."
HEALTHY=false
for i in $(seq 1 $HEALTH_RETRIES); do
    if curl -sf "http://localhost:$NEW_PORT/health" > /dev/null 2>&1; then
        HEALTHY=true
        echo "  Attempt $i: PASSED"
        break
    fi
    echo "  Attempt $i/$HEALTH_RETRIES: failed — retrying in ${HEALTH_INTERVAL}s..."
    sleep $HEALTH_INTERVAL
done

if [[ "$HEALTHY" != "true" ]]; then
    echo "ERROR: Health check failed after $HEALTH_RETRIES attempts."
    if [[ "$FIRST_DEPLOY" == "true" ]]; then
        docker compose down
    else
        docker compose stop "app-$NEW"
        echo "Nginx remains on app-$CURRENT. No traffic switched. Rolled back."
    fi
    exit 1
fi

# ── Switch nginx to the new slot (skipped on first deploy — already pointing there) ─
if [[ "$FIRST_DEPLOY" == "false" ]]; then
    echo "Switching nginx upstream to app-$NEW..."
    # Overwrite the host-side nginx.conf (bind-mounted into the nginx container)
    sed "s/{{ACTIVE_HOST}}/app-$NEW/g" nginx/nginx.conf.template > nginx/nginx.conf
    docker exec nginx nginx -s reload
    echo "Traffic switched to app-$NEW."

    echo "Stopping old slot app-$CURRENT..."
    docker compose stop "app-$CURRENT"
fi

echo "Deployment complete. Active slot: $NEW"
