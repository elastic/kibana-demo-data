#!/bin/sh

USERNAME="${KIBANA_DEMO_USERNAME:-elastic}"
PASSWORD="${KIBANA_DEMO_PASSWORD:-changeme}"
ES_URL="${KIBANA_DEMO_ES_URL:-http://localhost:9200}"

log() {
  # Echo the timestamp followed by the original message
  echo "[$(date "+%Y-%m-%dT%H:%M:%S%z")][search] - $1"
}

create_index_and_load_data() {
     index_name=$1
     mapping_url=$2
     data_url=$3

     # Step 1: Create the index with mapping
     log "Creating index ${index_name} with mapping from ${mapping_url}..."
     curl -s "${mapping_url}" | curl -u "${USERNAME}:${PASSWORD}" -X PUT "${ES_URL}/${index_name}" -H "Content-Type: application/json" -d @-> /dev/null 2>&1

     # Step 2: Load data into the index
     log "Loading data into ${index_name} from ${data_url}..."
     curl -s "${data_url}" | jq -c 'map(del(._id))[] | {"index":{}}, .' | curl -u "${USERNAME}:${PASSWORD}" -s -H 'Content-Type: application/x-ndjson' -XPOST "${ES_URL}/${index_name}/_bulk?pretty" --data-binary @- > /dev/null 2>&1
   }

   # Example usage:
   create_index_and_load_data "bike-hire-stations" \
     "https://raw.githubusercontent.com/searchkit/searchkit/refs/heads/main/sample-data/bike-hire-stations/mapping.json" \
     "https://raw.githubusercontent.com/searchkit/searchkit/refs/heads/main/sample-data/bike-hire-stations/stations.json"

   create_index_and_load_data "camping-sites" \
     "https://raw.githubusercontent.com/searchkit/searchkit/refs/heads/main/sample-data/camping-sites/mapping.json" \
     "https://raw.githubusercontent.com/searchkit/searchkit/refs/heads/main/sample-data/camping-sites/docs.json"

   create_index_and_load_data "movies" \
     "https://raw.githubusercontent.com/searchkit/searchkit/refs/heads/main/sample-data/movies/mapping.json" \
     "https://raw.githubusercontent.com/searchkit/searchkit/refs/heads/main/sample-data/movies/movies.json"

   create_index_and_load_data "mrp-products" \
     "https://raw.githubusercontent.com/searchkit/searchkit/refs/heads/main/sample-data/mrp-products/mapping.json" \
     "https://raw.githubusercontent.com/searchkit/searchkit/refs/heads/main/sample-data/mrp-products/data.json"

   create_index_and_load_data "parks" \
     "https://raw.githubusercontent.com/searchkit/searchkit/refs/heads/main/sample-data/mrp-products/mapping.json" \
     "https://raw.githubusercontent.com/searchkit/searchkit/refs/heads/main/sample-data/mrp-products/data.json"
