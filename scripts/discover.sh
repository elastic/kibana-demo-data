#!/bin/sh
# Installs the "discover" demo dataset: a rich, 7-tab Discover session
# (classic query, ES|QL, ES|QL group by, ES|QL metrics experience, traces
# experience, patterns, change point) plus a dashboard embedding that
# session, backed by real data, created in four demo spaces - one per
# solution type:
#   demo-classic (classic), demo-o11y (oblt), demo-security (security),
#   demo-search (es)
#
# Must be run from a Kibana checkout (for `node scripts/synthtrace`, used to
# seed the traces data). The companion scripts/discover_data.mjs does the
# rest (log/metrics indices, spaces, data views, Discover sessions) using
# only Node's built-in fetch, so it has no npm dependencies of its own.

USERNAME="${KIBANA_DEMO_USERNAME:-elastic}"
PASSWORD="${KIBANA_DEMO_PASSWORD:-changeme}"
ES_URL="${KIBANA_DEMO_ES_URL:-http://localhost:9200}"
KIBANA_URL="${KIBANA_DEMO_KIBANA_URL:-http://localhost:5601}"
SCRIPT_URL_BASE="https://elastic.github.io/kibana-demo-data/scripts"

log() {
  echo "[$(date "+%Y-%m-%dT%H:%M:%S%z")][discover] - $1"
}

log "Waiting for Elasticsearch to be online..."
while true; do
  response=$(curl -s -o /dev/null -w "%{http_code}" -u "${USERNAME}:${PASSWORD}" "${ES_URL}")
  [ "$response" = "200" ] && break
  printf "."
  sleep 5
done

log "Waiting for Kibana to be online..."
dev_prefix=""
while true; do
  response=$(curl -s -o /dev/null -w "%{http_code}" -u "${USERNAME}:${PASSWORD}" "${KIBANA_URL}${dev_prefix}/api/status")
  [ "$response" = "200" ] && break
  if [ -z "$dev_prefix" ]; then
    redirect=$(curl -s -o /dev/null -w "%{redirect_url}" "${KIBANA_URL}")
    case "$redirect" in
      *://*) dev_prefix="" ;;
      /*) dev_prefix="$redirect" ;;
    esac
  fi
  printf "."
  sleep 5
done

log "Seeding traces data via synthtrace (requires running from a Kibana checkout)..."
if [ -f "scripts/synthtrace.js" ]; then
  node scripts/synthtrace logs_traces_hosts --from now-3h --to now --target "$(printf '%s' "$ES_URL" | sed "s#://#://${USERNAME}:${PASSWORD}@#")" > /dev/null 2>&1 || true
  log "Traces data seeded."
else
  log "WARNING: scripts/synthtrace not found - run this script from a Kibana checkout to get the Traces Experience tab's data. Continuing without it."
fi

log "Seeding logs/metrics indices, spaces, and Discover sessions..."
data_script="/tmp/kibana-demo-data-discover_data.mjs"
if [ -f "$(dirname "$0")/discover_data.mjs" ]; then
  data_script="$(dirname "$0")/discover_data.mjs"
else
  curl -fsSL "${SCRIPT_URL_BASE}/discover_data.mjs" -o "$data_script"
fi

KIBANA_DEMO_USERNAME="$USERNAME" \
KIBANA_DEMO_PASSWORD="$PASSWORD" \
KIBANA_DEMO_ES_URL="$ES_URL" \
KIBANA_DEMO_KIBANA_URL="${KIBANA_URL}${dev_prefix}" \
node "$data_script"

log "Discover demo dataset installed. Open Discover in each space to explore:"
log "  ${KIBANA_URL}${dev_prefix}/s/demo-classic/app/discover"
log "  ${KIBANA_URL}${dev_prefix}/s/demo-o11y/app/discover"
log "  ${KIBANA_URL}${dev_prefix}/s/demo-security/app/discover"
log "  ${KIBANA_URL}${dev_prefix}/s/demo-search/app/discover"
