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
echo "Installing sample data"
echo "Install logs"
curl -u ${username}:${password} -X POST "${kibana_url}${dev_prefix}/api/sample_data/logs" -s -o /dev/null -H 'kbn-xsrf: true' -H 'Content-Type: application/json' 2>&1
echo "Install ecommerce"
curl -u ${username}:${password} -X POST "${kibana_url}${dev_prefix}/api/sample_data/ecommerce" -s -o /dev/null -H 'kbn-xsrf: true' -H 'Content-Type: application/json' 2>&1
echo "Install flights"
curl -u ${username}:${password} -X POST "${kibana_url}${dev_prefix}/api/sample_data/flights" -s -o /dev/null -H 'kbn-xsrf: true' -H 'Content-Type: application/json' 2>&1
echo "Install logstsdb"
curl -u ${username}:${password} -X POST "${kibana_url}${dev_prefix}/api/sample_data/logstsdb" -s -o /dev/null -H 'kbn-xsrf: true' -H 'Content-Type: application/json' 2>&1
echo "Sample data installed finished!"
