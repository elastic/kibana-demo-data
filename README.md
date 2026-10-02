
# Kibana Demo Data

This repository contains a script to quickly set up demo data for **Kibana** development and demonstration purposes. Before running the script, make sure you are in the **Kibana** directory. You can run the script on any **Kibana dev instance** that uses the default credentials (`elastic:changeme`) with the following command:

```bash
curl -sSL https://elastic.github.io/kibana-demo-data | sh
```

The script waits for the Kibana dev instance to be up and running, and then installs several sets of demo data automatically.

## One-Command Kibana Start & Data Ingestion

For convenience, you can start Kibana and ingest demo data in one command:

```bash
yarn start & curl -sSL https://elastic.github.io/kibana-demo-data | sh  
```

## Demo Data Sets Installed by the Script

The script installs several demo data sets, each with an associated variable name that can be used for selective installation:

- **Kibana Sample Data** (`sample`)
- **Custom Sample Data** from the [data](./data) folder of this repository (`custom`)
- **Basic Security Sample Data** (`security`)
- **Observability (O11y) Sample Data** (`o11y`)
- **Makelogs Sample Data** (`makelogs`)
- **Searchkit Data** (`searchkit`)
- **Metrics Sample Data** (`metrics`) - Uses [simian-forge](https://github.com/simianhacker/simian-forge) to generate host metrics data
- **Edge Case Data** with 50,000 dynamically generated unique fields across 10 indices (5,000 unique fields each) and 10 test documents for testing massive field scenarios (`edgecase`)
- **Discover Demo Data** (`discover`) - A rich, 11-tab Discover session (classic, classic ad hoc data view, field statistics, ES|QL, ES|QL group by, ES|QL view, metrics experience, traces experience, patterns, change point, data sources) plus a dashboard embedding that session, backed by real data, created in four demo spaces, one per solution type: `demo-classic` (classic), `demo-o11y` (oblt), `demo-security` (security), `demo-search` (es). The "Data Sources" tab queries a real public dataset (AWS Open Data Bitcoin blockchain, in S3) registered via ES|QL Data Federation; the "ES|QL View" tab queries a reusable named ES|QL view. Every tab and the dashboard store an explicit time range, so they reliably show data regardless of the viewer's default time range. The spaces are created only if they don't already exist, and the Discover session/dashboard IDs are deterministic (`demo-discover-session-<space-id>` / `demo-discover-dashboard-<space-id>`) so automated tests can reference them directly and re-running the script is idempotent. Requires a recent Kibana checkout (uses `node scripts/synthtrace` for traces data and the Discover session/Dashboard APIs), and an Elasticsearch version with ES|QL Data Federation and view support.

## Installing Specific Data Sets

If you want to install only specific subsets of data, use the following command with the appropriate data set options (e.g., `sample`, `custom`, `security`, `o11y`, `makelogs`,  `metrics`, `edgecase` or `discover`):

```bash
curl -sSL https://elastic.github.io/kibana-demo-data | sh -s <data_set>
```

For example, to install **Kibana Sample Data** and **Custom Sample Data** together, run:

```bash
curl -sSL  https://elastic.github.io/kibana-demo-data | sh -s sample custom
```

To install **Edge Case Data** with 50,000 dynamically generated unique fields across 10 indices and 10 test documents:

```bash
curl -sSL https://elastic.github.io/kibana-demo-data | sh -s edgecase
```

To install the **Discover Demo Data** (run from a Kibana checkout):

```bash
curl -sSL https://elastic.github.io/kibana-demo-data | sh -s discover
```
