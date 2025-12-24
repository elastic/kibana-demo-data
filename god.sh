#!/bin/sh
# A script to install all known demo data hidden in Kibana

username="elastic"
password="changeme"
url="http://localhost:9200"  # replace with your Elasticsearch URL if different
kibana_url="http://localhost:5601"  # replace with your Kibana URL if different
echo "🙏🙏🙏 Kibana demo data god ingestion script start 🙏🙏🙏"

echo "Waiting for Elasticsearch to be online..."
while true; do
    # Check if Elasticsearch is online
    response=$(curl -s -o /dev/null -w "%{http_code}" -u "${username}:${password}" ${url})

    if [ "$response" -eq 200 ]; then
        echo "Elasticsearch is online."
        break
    fi
    printf "."
    sleep 5
done

echo "Installing remote sample data to Elasticsearch"

process_remote() {
  remote_json_url=$1

  # Extract the base filename from the URL
  base_filename=$(basename "$remote_json_url" .ndjson)

  echo "Processing ${base_filename}"

  bulk_data_file=$(mktemp)
  counter=0
  curl -s "$remote_json_url" | while IFS= read -r line; do
    processed_line=$(echo "$line" | sed "s/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T/$(date +%Y-%m-%dT)/g")

    # Append the action and metadata to the bulk_data string
    echo "{ \"index\" : { \"_index\" : \"${base_filename}\" } }" >> "$bulk_data_file"

    # Append the document to the bulk_data string
    echo "${processed_line}" >> "$bulk_data_file"

    counter=$((counter+1))

    if [ $counter -eq 250 ]; then
      # Send the bulk_data string to Elasticsearch using the _bulk API
      curl -s -u "${username}:${password}" -s -X POST "${url}/_bulk" -H 'Content-Type: application/json' --data-binary "@$bulk_data_file" > /dev/null

      # Reset the counter and start a new batch
      counter=0
      rm "$bulk_data_file"
      bulk_data_file=$(mktemp)
    fi
  done

  # Send any remaining data in the last batch
  if [ $counter -gt 0 ]; then
    curl -s -u "${username}:${password}" -s -X POST "${url}/_bulk" -H 'Content-Type: application/json' --data-binary "@$bulk_data_file" > /dev/null
  fi
  # Clean up the temporary file
  if [ -f "$bulk_data_file" ]; then
    rm "$bulk_data_file"
  fi
  echo "Processing ${base_filename} completed"
}

process_remote "https://elastic.github.io/kibana-demo-data/data/log-apache.error.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-aws.s3.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-custom.multiplex.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-kubernetes.container_logs.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-nginx.error.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-nqinx.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-system.error.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/custom-metrics-without-timestamp.ndjson"

echo "Installing remote sample data to Elasticsearch finished"


echo "Waiting for Kibana to be online..."
while true; do
    # Check if the API status endpoint is available
    response=$(curl -v -u "${username}:${password}" ${kibana_url}${dev_prefix}/api/status 2>&1)

    if echo "$response" | grep -q "HTTP/.* 200 OK"; then
        break
    fi
    # Attempt to get the dev prefix of the instance
    if [[ -z "$dev_prefix" ]]; then
        response=$(curl -v ${kibana_url} 2>&1)
        if echo "$response" | grep -q "HTTP/1.1 302 Found"; then
          dev_prefix=$(echo "$response" | grep -i "location:" | cut -d':' -f2- | tr -d '[:space:]')
        fi
    fi
    printf "."
    sleep 5
done

echo "Kibana is now online!"



process_remote_kibana() {
  remote_json_url=$1

  # Extract the base filename from the URL
  base_filename=$(basename "$remote_json_url" .ndjson)

  echo "Provide ${base_filename} data views"

  curl -s -u "${username}:${password}" "${kibana_url}${dev_prefix}/api/data_views/data_view" -H 'kbn-xsrf: true' -H 'elastic-api-version: 2023-10-31' -H 'Content-Type: application/json' -d '
  {
    "data_view": {
       "title": "'"$base_filename"'",
       "name": "'"$base_filename"'",
       "timeFieldName": "@timestamp"
    }
  }' > /dev/null
}

echo "Installing remote sample data"

process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-apache.error.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-aws.s3.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-custom.multiplex.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-kubernetes.container_logs.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-nginx.error.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-nqinx.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-system.error.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/custom-metrics-without-timestamp.ndjson"


echo "Installing remote sample data finished"

echo "Installing security sample data"
yarn --cwd x-pack/plugins/security_solution test:generate --kibana http://${username}:${password}@localhost:5601${dev_prefix}
echo "Installing security sample data finished"

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

echo "🙏🙏🙏 Demo data ingestion script stop 🙏🙏🙏"
echo "🙏🙏🙏 The demo god is with you!! 🙏🙏🙏"
