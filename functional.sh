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
  #curl -s -u elastic:changeme -X DELETE "localhost:9200/testhuge" -H 'Content-Type: application/json' > /dev/null 2>&1

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

  # Recreate the index so a stale mapping from an earlier run cannot survive,
  # and fail loudly if it cannot be created with the fixture mapping.
  curl -s -o /dev/null -u "${username}:${password}" -X DELETE "${elasticsearch_url}/${FIXTURE_NAME}"
  local create_body create_status
  create_body=$(mktemp)
  create_status=$(curl -s -o "$create_body" -w "%{http_code}" -u "${username}:${password}" -X PUT "${elasticsearch_url}/${FIXTURE_NAME}" -H 'Content-Type: application/json' --data-binary @- <<< "$MODIFIED_JSON")
  if [[ "$create_status" != 2* ]]; then
    echo "Failed to create index $FIXTURE_NAME: HTTP $create_status $(cat "$create_body")"
    rm -f "$create_body"
    exit 1
  fi
  rm -f "$create_body"

  echo "$FIXTURE_PATH - process data"
  local indexed=0 failed=0 doc_status
  while IFS= read -r block; do
    # Check if the block is non-empty
    if [[ -n "$block" ]]; then
      # Extract the id from the payload
      id=$(echo "$block" | jq -r '.value.id')

      type=$(echo "$block" | jq -r '.type')

      # Remove the outer 'type' and 'value' fields, keeping only the 'source'
      source=$(echo "$block" | jq -c '.value.source')

      # Post the modified payload to Elasticsearch
      if [[ "$type" == "doc" ]]; then
        doc_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${username}:${password}" -X POST "${elasticsearch_url}/${FIXTURE_NAME}/_doc/${id}" -H 'Content-Type: application/json' --data-binary @- <<< "$source")
        if [[ "$doc_status" == 2* ]]; then
          indexed=$((indexed + 1))
        else
          failed=$((failed + 1))
          echo "  Failed to index doc $id into $FIXTURE_NAME: HTTP $doc_status"
        fi
      fi
    fi
  done < <(gunzip -c "$DATA_FILE_PATH" | jq -c --slurp '.[]')

  echo "$FIXTURE_PATH - indexed $indexed docs, $failed failed"
  if [[ $failed -ne 0 || $indexed -eq 0 ]]; then
    echo "Fixture $FIXTURE_NAME is incomplete or empty."
    exit 1
  fi

  echo "$FIXTURE_PATH - done"
}

# Process multiple fixtures
#process_fixture "src/platform/test/functional/fixtures/es_archiver/huge_fields"  # fixture removed upstream
process_fixture "src/platform/test/functional/fixtures/es_archiver/many_fields"

#process_fixture "src/platform/test/functional/fixtures/es_archiver/search/downsampled"
