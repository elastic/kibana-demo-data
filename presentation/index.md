---
theme: uncover

---
![bg left:20% 80%](./kibana.png)
<style scoped>
section {
    font-size: 30px;
}
</style>
# Kibana Demo Data

* Repository: [github.com/elastic/kibana-demo-data](https://github.com/elastic/kibana-demo-data)
* Quicker data ingestion for Kibana dev instances
* Part of [Kibana a la carte](https://kibana-a-la-carte.kbndev.co/) 🍜
* ON week project cleaned up

---
# Add custom demo data

A small sample of nginx, apache, s3, kubernetes, system logs

```sh
curl -sSL https://elastic.github.io/kibana-demo-data | sh -s custom
```

---

# Add o11y data

Sample data provided my o11y synthtrace tool

```sh
curl -sSL https://elastic.github.io/kibana-demo-data | sh -s o11y
```

# Add security data

Small sample of security demo data
```sh
curl -sSL https://elastic.github.io/kibana-demo-data | sh -s security
```

---

# Add makelogs data

1 million of good old Kibana makelogs documents
```sh
curl -sSL https://elastic.github.io/kibana-demo-data | sh -s makelogs
```

---

# Add it all

Can't decide? Add all the data sets

```sh
curl -sSL https://elastic.github.io/kibana-demo-data | sh
```
Or some of them together
```sh
curl -sSL https://elastic.github.io/kibana-demo-data | sh -s custom o11y
```

---

# Add it while starting Kibana

Less clicks, quicker data in your fresh Kibana automatically
```sh
yarn start & curl -sSL https://elastic.github.io/kibana-demo-data | sh 
```
---
# Hope it saves you some time


