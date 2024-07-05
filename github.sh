#!/bin/sh

# Configuration
USERNAME="elastic"
PASSWORD="changeme"
GITHUB_REPO_OWNER="elastic"
GITHUB_REPO_NAME="kibana"
GITHUB_LABEL="Team:DataDiscovery"
ELASTICSEARCH_HOST="localhost"
ELASTICSEARCH_PORT="9200"
INDEX_NAME="github_prs"
PAGE=1
PER_PAGE=100

# Function to fetch issues by label
fetch_issues() {
  curl -s "https://api.github.com/repos/$GITHUB_REPO_OWNER/$GITHUB_REPO_NAME/issues?labels=$GITHUB_LABEL&state=all&page=$PAGE&per_page=$PER_PAGE"
}

# Function to ingest PRs into Elasticsearch
ingest_pr() {
  curl -o /dev/null -s -u $USERNAME:$PASSWORD -X POST "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/$INDEX_NAME/_doc/" -H 'Content-Type: application/json' -d "$1"
}

# Fetch and ingest PRs by label with pagination
echo "Github PR ingestion started"
while true; do
  # Fetch issues and filter PRs, then ingest each PR
  fetch_issues | jq -c '.[] | select(.pull_request)' | while read -r pr; do
    ingest_pr "$pr"
  done

  # Check if there are no more issues
  if [ $(fetch_issues | jq length) -eq 0 ]; then
    break
  fi

  # Increment page
  #PAGE=$((PAGE + 1))
  break
done

echo "Github PR ingestion finished"
