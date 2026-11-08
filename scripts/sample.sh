#!/bin/sh
# A script to install all known demo data hidden in Kibana

username="elastic"
password="changeme"
kibana_url="http://localhost:5601"  # replace with your Kibana URL if different

echo "Waiting for Kibana to be online..."
while true; do
    # Check if the API status endpoint is available
    response=$(curl -v -u "${username}:${password}" ${kibana_url}${dev_prefix}/api/status 2>&1)

    if echo "$response" | grep -q "HTTP/.* 200 OK"; then
        break
    fi
    # Attempt to get the dev prefix of the instance
    if [ -z "$dev_prefix" ]; then
        response=$(curl -v ${kibana_url} 2>&1)
        if echo "$response" | grep -q "HTTP/1.1 302 Found"; then
          dev_prefix=$(echo "$response" | grep -i "location:" | cut -d':' -f2- | tr -d '[:space:]')
        fi
    fi
    printf "."
    sleep 5
done

echo "Kibana is now online!"
# Install sample data using curl
# These are internal Kibana routes: they are rejected with a 400 unless the
# x-elastic-internal-origin header is sent.
failed=0
install_sample() {
    echo "Install $1"
    body=$(mktemp)
    status=$(curl -s -o "$body" -w "%{http_code}" -u "${username}:${password}" -X POST \
        "${kibana_url}${dev_prefix}/api/sample_data/$1" \
        -H 'kbn-xsrf: true' -H 'x-elastic-internal-origin: Kibana' -H 'Content-Type: application/json')
    if [ "$status" != "200" ]; then
        echo "  FAILED ($1): HTTP $status $(cat "$body")"
        failed=1
    fi
    rm -f "$body"
}

install_sample logs
install_sample ecommerce
install_sample flights
install_sample logstsdb

if [ "$failed" -ne 0 ]; then
    echo "Sample data installation finished with errors!"
    exit 1
fi
echo "Sample data installation finished!"
