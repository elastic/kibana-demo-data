#!/bin/bash
# A script to install edge case data for Kibana testing

username="elastic"
password="changeme"
elasticsearch_url="http://localhost:9200"  # replace with your Elasticsearch URL if different

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

  echo "$FIXTURE_PATH - process mappings"

  # Load and modify the JSON file
  if ! MODIFIED_JSON=$(jq '{
    settings: .value.settings,
    mappings: .value.mappings
  }' "$MAPPING_FILE_PATH"); then
    echo "Failed to modify JSON file."
    exit 1
  fi

  # get the value.index, assign it to $FIXTURE_NAME
  FIXTURE_NAME=$(jq -r '.value.index' "$MAPPING_FILE_PATH")

  # Delete existing index if it exists (optional cleanup)
  curl -s -u "${username}:${password}" -X DELETE "${elasticsearch_url}/${FIXTURE_NAME}" -H 'Content-Type: application/json' > /dev/null 2>&1

  # Create the index with mappings and settings
  curl -s -u "${username}:${password}" -X PUT "${elasticsearch_url}/${FIXTURE_NAME}" -H 'Content-Type: application/json' -d "$MODIFIED_JSON" > /dev/null 2>&1

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
        curl -s -u "${username}:${password}" -X POST "${elasticsearch_url}/${FIXTURE_NAME}/_doc/$id" -H 'Content-Type: application/json' -d "$source" > /dev/null 2>&1
      fi
    fi
  done

  echo "$FIXTURE_PATH - done"
}

# Download the fixture data from the repository if it doesn't exist locally
FIXTURE_DIR="test/functional/fixtures/es_archiver/huge_fields"
if [ ! -d "$FIXTURE_DIR" ]; then
  echo "Creating fixture directory and downloading data..."
  mkdir -p "$FIXTURE_DIR"
  
  # Download mappings.json
  curl -s "https://elastic.github.io/kibana-demo-data/$FIXTURE_DIR/mappings.json" -o "$FIXTURE_DIR/mappings.json"
  
  # Download data.json.gz
  curl -s "https://elastic.github.io/kibana-demo-data/$FIXTURE_DIR/data.json.gz" -o "$FIXTURE_DIR/data.json.gz"
fi

# Process the fixture
process_fixture "$FIXTURE_DIR"

echo "Edge case data installation complete!"