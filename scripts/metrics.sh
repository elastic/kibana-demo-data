#!/bin/sh

USERNAME="${KIBANA_DEMO_USERNAME:-elastic}"
PASSWORD="${KIBANA_DEMO_PASSWORD:-changeme}"
ELASTICSEARCH_URL="${KIBANA_DEMO_ES_URL:-http://localhost:9200}"
FORGE_REPO="https://github.com/simianhacker/simian-forge"
FORGE_DIR="../simian-forge"

log() {
  # Echo the timestamp followed by the original message
  echo "[$(date "+%Y-%m-%dT%H:%M:%S%z")][metrics] - $1"
}

log "Starting metrics data ingestion"

# Wait for Elasticsearch to be online
log "Waiting for Elasticsearch to be online..."
while true; do
    response=$(curl -s -o /dev/null -w "%{http_code}" -u "${USERNAME}:${PASSWORD}" ${ELASTICSEARCH_URL})
    
    if [ "$response" -eq 200 ]; then
        log "Elasticsearch is online."
        break
    fi
    printf "."
    sleep 5
done

# Check if simian-forge directory exists
if [ ! -d "${FORGE_DIR}" ]; then
    log "simian-forge not found in parent directory. Cloning repository..."
    git clone "${FORGE_REPO}" "${FORGE_DIR}"
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to clone simian-forge repository"
        exit 1
    fi
    log "Repository cloned successfully"
fi

# Navigate to forge directory
cd "${FORGE_DIR}" || {
    log "ERROR: Failed to navigate to ${FORGE_DIR}"
    exit 1
}

# Check if node_modules exists, if not run npm install
if [ ! -d "node_modules" ]; then
    log "Installing dependencies..."
    npm install
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to install dependencies"
        exit 1
    fi
    log "Dependencies installed successfully"
fi

# Check if forge executable exists, if not run npm run build
if [ ! -f "dist" ]; then
    log "Building simian-forge..."
    npm run build
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to build simian-forge"
        exit 1
    fi
    log "Build completed successfully"
fi

# Run forge command to ingest metrics data
log "Ingesting metrics data with forge..."
./forge --dataset hosts --count 25 --interval 30s --no-realtime --backfill now-1h --elasticsearch-url ${ELASTICSEARCH_URL} --elasticsearch-auth ${USERNAME}:${PASSWORD}

if [ $? -eq 0 ]; then
    log "Metrics data ingestion completed successfully"
else
    log "WARNING: Forge command exited with non-zero status, but may have ingested some data"
fi
