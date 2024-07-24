#!/bin/sh

USERNAME="elastic"
PASSWORD="changeme"
ELASTICSEARCH_URL="http://localhost:9200"  # replace with your Elasticsearch URL if different
KIBANA_URL="http://localhost:5601"  # replace with your Kibana URL if different

log() {
  # Echo the timestamp followed by the original message
  echo "[$(date "+%Y-%m-%dT%H:%M:%S%z")][makelogs] - $1"
}

log "start"


while true; do
    # Check if Elasticsearch is online
    response=$(curl -s -o /dev/null -w "%{http_code}" -u "${USERNAME}:${PASSWORD}" ${ELASTICSEARCH_URL})

    if [ "$response" -eq 200 ]; then
        log "Elasticsearch is online."
        break
    fi
    sleep 5
done

node scripts/makelogs.js -h ${ELASTICSEARCH_URL} --reset --auth ${USERNAME}:${PASSWORD}  -c 1000000
log "finished"