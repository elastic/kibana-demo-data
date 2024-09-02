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

echo "Installing o11y synthtrace sample data"

files="azure_functions.ts cloud_services_icons.ts continuous_rollups.ts degraded_logs.ts distributed_trace.ts distributed_trace_long.ts distributed_trace_long.ts high_throughput.ts high_throughput.ts high_throughput.ts infra_hosts_with_apm_hosts.ts logs_and_metrics.ts low_throughput.ts many_dependencies.ts many_errors.ts many_services.ts other_bucket_group.ts many_transactions.ts mobile.ts service_map.ts service_map_oom.ts service_summary_field_version_dependent.ts services_without_transactions.ts simple_logs.ts simple_trace.ts span_links.ts spiked_latency.ts trace_with_orphan_items.ts traces_logs_assets.ts variance.ts"

for file in $files;
do
  node scripts/synthtrace "$file" > /dev/null 2>&1 || true
done
echo "Installing o11y synthtrace sample data finished"

curl -s -u "${username}:${password}" "${kibana_url}${dev_prefix}/api/data_views/data_view" -H 'kbn-xsrf: true' -H 'elastic-api-version: 2023-10-31' -H 'Content-Type: application/json' -d '
  {
    "data_view": {
       "title": "log*",
       "name": "log*",
       "timeFieldName": "@timestamp"
    }
  }' > /dev/null

