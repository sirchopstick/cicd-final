# deploy.ps1 — Blue-Green deployment (PowerShell version for Windows self-hosted runner)
$ErrorActionPreference = "Stop"

$HEALTH_RETRIES = 10
$HEALTH_INTERVAL = 3

# ── Detect current active slot from running nginx container ──────────────────
$FIRST_DEPLOY = $false
$CURRENT = ""

docker inspect nginx 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    $nginxConf = docker exec nginx cat /etc/nginx/nginx.conf 2>$null
    if ($nginxConf -match "app-(blue|green)") {
        $CURRENT = $Matches[1]
    }
} else {
    $FIRST_DEPLOY = $true
}

# ── Determine target slot ────────────────────────────────────────────────────
if ($CURRENT -eq "blue") {
    $NEW = "green"; $NEW_PORT = 8002
} else {
    $NEW = "blue"; $NEW_PORT = 8001
}

Write-Host "Current active slot : $(if ($CURRENT) { $CURRENT } else { 'none' }) (first deploy: $FIRST_DEPLOY)"
Write-Host "Deploying to        : $NEW (port $NEW_PORT)"

# ── First deploy: generate nginx config and start the full stack ─────────────
if ($FIRST_DEPLOY) {
    Write-Host "First deploy: generating nginx config and starting stack..."
    $conf = (Get-Content nginx/nginx.conf.template -Raw) -replace "{{ACTIVE_HOST}}", "app-$NEW"
    Set-Content nginx/nginx.conf $conf -NoNewline
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { exit 1 }
} else {
    Write-Host "Updating app-$NEW with the latest image..."
    docker compose up -d --no-deps --force-recreate "app-$NEW"
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

# ── Health check loop ────────────────────────────────────────────────────────
Write-Host "Waiting for app-$NEW to pass health check..."
$HEALTHY = $false
for ($i = 1; $i -le $HEALTH_RETRIES; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$NEW_PORT/health" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($r.StatusCode -eq 200) {
            Write-Host "  Attempt ${i}: PASSED"
            $HEALTHY = $true
            break
        }
    } catch {
        Write-Host "  Attempt ${i}/${HEALTH_RETRIES}: failed — retrying in ${HEALTH_INTERVAL}s..."
        Start-Sleep -Seconds $HEALTH_INTERVAL
    }
}

if (-not $HEALTHY) {
    Write-Host "ERROR: Health check failed after ${HEALTH_RETRIES} attempts."
    if ($FIRST_DEPLOY) {
        docker compose down
    } else {
        docker compose stop "app-$NEW"
        Write-Host "Nginx remains on app-$CURRENT. No traffic switched. Rolled back."
    }
    exit 1
}

# ── Switch nginx to the new slot (skipped on first deploy) ───────────────────
if (-not $FIRST_DEPLOY) {
    Write-Host "Switching nginx upstream to app-$NEW..."
    $conf = (Get-Content nginx/nginx.conf.template -Raw) -replace "{{ACTIVE_HOST}}", "app-$NEW"
    Set-Content nginx/nginx.conf $conf -NoNewline
    docker exec nginx nginx -s reload
    if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: nginx reload failed"; exit 1 }
    Write-Host "Traffic switched to app-$NEW."

    Write-Host "Stopping old slot app-$CURRENT..."
    docker compose stop "app-$CURRENT"
}

Write-Host "Deployment complete. Active slot: $NEW"
