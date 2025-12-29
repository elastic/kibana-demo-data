
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


## Installing Specific Data Sets

If you want to install only specific subsets of data, use the following command with the appropriate data set options (e.g., `sample`, `custom`, `security`, `o11y`, `makelogs`, `metrics`, or `edgecase`):

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
