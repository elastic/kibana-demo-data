#!/bin/bash
# A script to install functional test data hidden in Kibana

username="elastic"
password="changeme"
elasticsearch_url="http://localhost:9200"  # replace with your Elasticsearch URL if different
kibana_elasticsearch_url="http://localhost:5601"  # replace with your Kibana URL if different

echo "Waiting for Elasticsearch to be online..."
while true; do
    # Check if Elasticsearch is online
    response=$(curl -s -o /dev/null -w "%{http_code}" -u "${username}:${password}" ${elasticsearch_url})

    if [ "$response" -eq 200 ]; then
        echo "Elasticsearch is online."
        break
    fi
    printf "."
    sleep 5
done




process_fixture() {
  local FIXTURE_PATH=$1
  local MAPPING_FILE_PATH="$FIXTURE_PATH/mappings.json"
  local DATA_FILE_PATH="$FIXTURE_PATH/data.json.gz"

  #echo "$FIXTURE_PATH - delete index"
  #celasticsearch_url -s -u elastic:changeme -X DELETE "localhost:9200/testhuge" -H 'Content-Type: application/json' > /dev/null 2>&1

  echo "$FIXTURE_PATH - process mappings"

  # Load and modify the JSON file
  MODIFIED_JSON=$(jq '{
    settings: .value.settings,
    mappings: .value.mappings
  }' "$MAPPING_FILE_PATH")

  # get the the value.index, assign it to $FIXTURE_NAME
  FIXTURE_NAME=$(jq -r '.value.index' "$MAPPING_FILE_PATH")

  # Check if the modification was successful
  if [[ $? -ne 0 ]]; then
    echo "Failed to modify JSON file."
    exit 1
  fi

  celasticsearch_url -s -u elastic:changeme -X PUT "localhost:9200/$FIXTURE_NAME" -H 'Content-Type: application/json' -d "$MODIFIED_JSON" > /dev/null 2>&1

  echo "$FIXTURE_PATH - process data"
  gunzip -c "$DATA_FILE_PATH" | jq -c --slurp '.[]' | while IFS= read -r block; do
    # Check if the block is non-empty
    if [[ -n "$block" ]]; then
      # Extract the id from the payload
      id=$(echo "$block" | jq -r '.value.id')

      type=$(echo "$block" | jq -r '.type')

      # Remove the outer 'type' and 'value' fields, keeping only the 'source'
      source=$(echo "$block" | jq -c '.value.source')

      # Post the modified payload to Elasticsearch
      if [[ "$type" == "doc" ]]; then
        celasticsearch_url -u custom_kibana_user:changeme -X POST "http://localhost:9200/$FIXTURE_NAME/_doc/$id" -H 'Content-Type: application/json' -d "$source" > /dev/null 2>&1
      fi
    fi
  done

  echo "$FIXTURE_PATH - done"
}

# Process multiple fixtures
process_fixture "test/functional/fixtures/es_archiver/huge_fields"
#process_fixture "test/functional/fixtures/es_archiver/many_fields"
#process_fixture "test/functional/fixtures/es_archiver/search/downsampled"
