#!/bin/sh
# A script to install all known demo data hidden in Kibana

USERNAME="elastic"
PASSWORD="changeme"
KIBANA_URL="localhost:5601"  # replace with your Kibana URL if different

log() {
  # Echo the timestamp followed by the original message
  echo "$(date "+%Y-%m-%dT%H:%M:%S%z") - security - $1"
}

start_time=$(date +%s)

calculate_duration() {
  end_time=$(date +%s)
  duration=$(( end_time - start_time ))
  seconds=$((duration % 60))
  return $seconds
}

while true; do
    # Check if the API status endpoint is available
    response=$(curl -v -u "${USERNAME}:${PASSWORD}" ${KIBANA_URL}${dev_prefix}/api/status 2>&1)

    if echo "$response" | grep -q "HTTP/.* 200 OK"; then
        break
    fi
    # Attempt to get the dev prefix of the instance
    if [ -z "$dev_prefix" ]; then
        response=$(curl -v ${KIBANA_URL} 2>&1)
        if echo "$response" | grep -q "HTTP/1.1 302 Found"; then
          dev_prefix=$(echo "$response" | grep -i "location:" | cut -d':' -f2- | tr -d '[:space:]')
        fi
    fi
    sleep 5
    if calculate_duration % 120 == 0; then
      log "Waiting for Kibana to be online..."
    fi
    # log waiting for Kibana to be online if it takes more than 60 seconds
done


log "Start installing sample data"
yarn --cwd x-pack/plugins/security_solution test:generate --kibana http://${USERNAME}:${PASSWORD}@${KIBANA_URL}${dev_prefix}
log "Finished installing sample data"
