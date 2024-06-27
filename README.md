# Kibana demo data - god
This repository contains a script that can be run in the following way in any Kibana dev instance, the goal is to quickly setup demo data for development and demonstration purpose.

```
curl -sSL http://elastic.github.io/kibana-demo-data/god.sh | sh
```

This script waits for the Kibana dev instance to be up an running and then it installs several different sets of demo data

1. Kibana Sample Data
2. Various Sample data provided in the [data](./data) folder of this repository
3. A basic set of security sample data
4. Synthrace sample data

May the demo gods be with you, now in an automatic way!


