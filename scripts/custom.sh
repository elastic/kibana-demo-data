#!/bin/sh
# A script to install custom demo data

USERNAME="elastic"
PASSWORD="changeme"
url="http://localhost:9200"  # replace with your Elasticsearch URL if different
kibana_url="http://localhost:5601"  # replace with your Kibana URL if different
echo "🙏🙏🙏 Kibana demo data god ingestion script start 🙏🙏🙏"

echo "Waiting for Elasticsearch to be online..."
while true; do
    # Check if Elasticsearch is online
    response=$(curl -s -o /dev/null -w "%{http_code}" -u "${USERNAME}:${PASSWORD}" ${url})

    if [ "$response" -eq 200 ]; then
        echo "Elasticsearch is online."
        break
    fi
    printf "."
    sleep 5
done

echo "Installing custom sample data to Elasticsearch"

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
      curl -s -u "${USERNAME}:${PASSWORD}" -s -X POST "${url}/_bulk" -H 'Content-Type: application/json' --data-binary "@$bulk_data_file" > /dev/null

      # Reset the counter and start a new batch
      counter=0
      rm "$bulk_data_file"
      bulk_data_file=$(mktemp)
    fi
  done

  # Send any remaining data in the last batch
  if [ $counter -gt 0 ]; then
    curl -s -u "${USERNAME}:${PASSWORD}" -s -X POST "${url}/_bulk" -H 'Content-Type: application/json' --data-binary "@$bulk_data_file" > /dev/null
  fi
  # Clean up the temporary file
  if [ -f "$bulk_data_file" ]; then
    rm "$bulk_data_file"
  fi
  echo "Processing ${base_filename} completed"
}

process_remote "https://elastic.github.io/kibana-demo-data/data/log-apache_error.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-aws_s3.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-custom_multiplex.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-k8s_container.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-nginx_error.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-nqinx.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/log-system_error.ndjson"
process_remote "https://elastic.github.io/kibana-demo-data/data/custom-metrics-without-timestamp.ndjson"

echo "Installing custom sample data to Elasticsearch finished"

echo "Waiting for Kibana to be online..."
while true; do
    # Check if the API status endpoint is available
    response=$(curl -v -u "${USERNAME}:${PASSWORD}" ${kibana_url}${dev_prefix}/api/status 2>&1)

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



process_remote_kibana() {
  remote_json_url=$1

  # Extract the base filename from the URL
  base_filename=$(basename "$remote_json_url" .ndjson)

  echo "Provide ${base_filename} data views"

  curl -s -u "${USERNAME}:${PASSWORD}" "${kibana_url}${dev_prefix}/api/data_views/data_view" -H 'kbn-xsrf: true' -H 'elastic-api-version: 2023-10-31' -H 'Content-Type: application/json' -d '
  {
    "data_view": {
       "title": "'"$base_filename"'",
       "name": "'"$base_filename"'",
       "timeFieldName": "@timestamp"
    }
  }' > /dev/null
}

echo "Installing custom sample data, Kibana part"

process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-apache_error.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-aws_s3.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-custom_multiplex.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-k8s_container.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-nginx_error.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-nqinx.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/log-system_error.ndjson"
process_remote_kibana "https://elastic.github.io/kibana-demo-data/data/custom-metrics-without-timestamp.ndjson"


echo "Installing custom sample data finished"

