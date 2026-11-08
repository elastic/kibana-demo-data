#!/bin/sh
# Installs small, targeted edge-case indices for testing Discover, field
# lists, data views and ES|QL. Complements edgecase.sh (many fields).
#
# Indices (all prefixed "edge-"):
#   edge-conflict-a / edge-conflict-b  same field names, different types -> conflicts in data view "edge-conflict-*"
#   edge-special-values                unicode, RTL, emoji, HTML/JS, empty/null/array values, huge numbers, long strings
#   edge-field-names                   dots, spaces, unicode, leading underscores, very long field names
#   edge-field-types                   exotic types: flattened, ranges, geo_shape, version, wildcard, histogram, ...
#   edge-timestamps                    epoch 0, far future, date_nanos, offsets, missing/invalid @timestamp
#   edge-deep-nesting                  objects nested 19 levels deep + nested type + arrays of objects
#   edge-high-cardinality              20,000 docs with unique keyword/ip values
#   edge-large-docs                    docs with ~100 KB text values
#   edge-no-timestamp                  index without any date field (data view without time field)

USERNAME="${KIBANA_DEMO_USERNAME:-elastic}"
PASSWORD="${KIBANA_DEMO_PASSWORD:-changeme}"
ES_URL="${KIBANA_DEMO_ES_URL:-http://localhost:9200}"

log() { echo "[$(date "+%Y-%m-%dT%H:%M:%S%z")][edgecase_values] - $1"; }

# es METHOD PATH [content-type]; request body on stdin
es() {
    curl -s -u "${USERNAME}:${PASSWORD}" -X "$1" "${ES_URL}$2" \
        -H "Content-Type: ${3:-application/json}" --data-binary @-
}

log "Waiting for Elasticsearch..."
until [ "$(curl -s -o /dev/null -w '%{http_code}' -u "${USERNAME}:${PASSWORD}" "${ES_URL}")" = "200" ]; do
    sleep 5
done

# recreate INDEX; mapping JSON on stdin
recreate() {
    curl -s -o /dev/null -u "${USERNAME}:${PASSWORD}" -X DELETE "${ES_URL}/$1"
    out=$(es PUT "/$1")
    case "$out" in
        *'"acknowledged":true'*) ;;
        *) log "FAILED to create $1: $out" ;;
    esac
}

# bulk INDEX; NDJSON action/doc pairs on stdin
bulk() {
    out=$(es POST "/$1/_bulk?refresh=true" application/x-ndjson)
    case "$out" in
        *'"errors":true'*)
            log "bulk $1 had rejected docs (some are deliberately invalid):"
            echo "$out" | grep -o '"reason":"[^"]*"' | sort -u | head -5 | sed 's/^/    /'
            ;;
    esac
}

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TOMORROW=$(date -u -v+1d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '+1 day' +"%Y-%m-%dT%H:%M:%SZ")
I='{"index":{}}'

# --- conflicting types -------------------------------------------------------
log "edge-conflict-a / edge-conflict-b"
recreate edge-conflict-a <<'JSON'
{"mappings":{"properties":{"@timestamp":{"type":"date"},"status":{"type":"keyword"},"value":{"type":"long"},"when":{"type":"date"},"client":{"type":"ip"},"tags":{"type":"keyword"},"geo":{"type":"geo_point"},"only_in_a":{"type":"keyword"}}}}
JSON
recreate edge-conflict-b <<'JSON'
{"mappings":{"properties":{"@timestamp":{"type":"date"},"status":{"type":"long"},"value":{"type":"text"},"when":{"type":"keyword"},"client":{"type":"keyword"},"tags":{"type":"text"},"geo":{"type":"keyword"},"only_in_b":{"type":"boolean"}}}}
JSON
bulk edge-conflict-a <<EOF
$I
{"@timestamp":"$NOW","status":"ok","value":1,"when":"2024-01-01T00:00:00Z","client":"10.0.0.1","tags":["a","b"],"geo":{"lat":52.5,"lon":13.4},"only_in_a":"x"}
$I
{"@timestamp":"$NOW","status":"error","value":2,"when":"2024-06-01T12:00:00Z","client":"::1","tags":"c","geo":"52.5,13.4","only_in_a":"y"}
EOF
bulk edge-conflict-b <<EOF
$I
{"@timestamp":"$NOW","status":200,"value":"one","when":"yesterday","client":"not-an-ip","tags":"free text here","geo":"u33dc0","only_in_b":true}
$I
{"@timestamp":"$NOW","status":404,"value":"two","when":"2024-01-01","client":"10.0.0.2","tags":["x y","z"],"geo":"somewhere","only_in_b":false}
EOF

# --- special values ----------------------------------------------------------
log "edge-special-values"
LONG=$(awk 'BEGIN{for(i=0;i<2000;i++) printf "word%d ", i}')
LONGKW=$(awk 'BEGIN{for(i=0;i<1500;i++) printf "k"}')
recreate edge-special-values <<'JSON'
{"mappings":{"properties":{"@timestamp":{"type":"date"},"text":{"type":"text","fields":{"keyword":{"type":"keyword","ignore_above":256}}},"kw":{"type":"keyword","ignore_above":1024},"num":{"type":"double"},"big":{"type":"unsigned_long"},"scaled":{"type":"scaled_float","scaling_factor":100},"int":{"type":"long"},"flag":{"type":"boolean"},"arr":{"type":"keyword"},"obj":{"type":"object"}}}}
JSON
bulk edge-special-values <<EOF
$I
{"@timestamp":"$NOW","text":"Ünïcödé: 日本語のテキスト, 中文, العربية, עברית, Ελληνικά, हिन्दी","kw":"日本語","num":1.5}
$I
{"@timestamp":"$NOW","text":"Emoji 🚀🔥👩‍👩‍👧‍👦 and combining é and zero​width","kw":"🚀","num":-0.0}
$I
{"@timestamp":"$NOW","text":"<script>alert('xss')</script><img src=x onerror=alert(1)>","kw":"<b>bold</b> & \"quotes\" 'single' \\\\ backslash","num":3.14159265358979}
$I
{"@timestamp":"$NOW","text":"","kw":"","num":0,"flag":false,"arr":[]}
$I
{"@timestamp":"$NOW","text":null,"kw":null,"num":null,"flag":null,"arr":null}
$I
{"@timestamp":"$NOW","text":"   ","kw":"   leading and trailing   ","num":1e300,"int":9223372036854775807,"big":18446744073709551615}
$I
{"@timestamp":"$NOW","num":-1e300,"int":-9223372036854775808,"scaled":123.456,"flag":"true"}
$I
{"@timestamp":"$NOW","kw":"line1\nline2\ttabbed\r\nline3","text":"multi\nline\ntext"}
$I
{"@timestamp":"$NOW","arr":["a","b","a",null,"","c"],"obj":{"x":1,"y":[1,2,3]}}
$I
{"@timestamp":"$NOW","arr":"single","obj":[{"x":1},{"x":2},{"y":"mixed"}]}
$I
{"@timestamp":"$NOW","kw":"$LONGKW","text":"$LONG"}
$I
{"@timestamp":"$NOW","kw":"http://example.com/path?query=1&b=2#frag","text":"user@example.com 192.168.1.1 2024-01-01T00:00:00Z"}
$I
{"@timestamp":"$NOW","kw":"*? wildcard : colon \\\\ AND OR NOT ( ) [ ] { } ^ ~","text":"KQL/Lucene reserved characters: + - = && || > < ! ( ) { } [ ] ^ ~ * ? : \\\\ /"}
EOF

# --- weird field names -------------------------------------------------------
log "edge-field-names"
LONGNAME=$(awk 'BEGIN{for(i=0;i<10;i++) printf "very_long_field_name_"}')
recreate edge-field-names <<JSON
{"mappings":{"properties":{"@timestamp":{"type":"date"},"with space":{"type":"keyword"},"with-dash":{"type":"keyword"},"UPPER_Case":{"type":"keyword"},"_leading_underscore":{"type":"keyword"},"日本語フィールド":{"type":"keyword"},"emoji_🚀":{"type":"keyword"},"a.b.c":{"type":"keyword"},"dotted":{"properties":{"name":{"type":"keyword"}}},"colon:name":{"type":"keyword"},"quote\"d":{"type":"keyword"},"${LONGNAME}":{"type":"keyword"},"0123":{"type":"keyword"},"count":{"type":"long"},"message":{"type":"text"}}}}
JSON
bulk edge-field-names <<EOF
$I
{"@timestamp":"$NOW","with space":"v1","with-dash":"v2","UPPER_Case":"v3","_leading_underscore":"v4","日本語フィールド":"v5","emoji_🚀":"v6","a.b.c":"v7","dotted.name":"v8","colon:name":"v9","quote\"d":"v10","${LONGNAME}":"v11","0123":"v12","count":1,"message":"field names that need escaping in KQL, ES|QL and Lucene"}
EOF

# --- exotic field types ------------------------------------------------------
log "edge-field-types"
recreate edge-field-types <<'JSON'
{"mappings":{"properties":{"@timestamp":{"type":"date"},"flat":{"type":"flattened"},"int_range":{"type":"integer_range"},"date_range":{"type":"date_range"},"ip_range":{"type":"ip_range"},"area":{"type":"geo_shape"},"pt":{"type":"geo_point"},"xy":{"type":"point"},"ver":{"type":"version"},"wild":{"type":"wildcard"},"const":{"type":"constant_keyword","value":"always"},"hist":{"type":"histogram"},"bin":{"type":"binary"},"vec":{"type":"dense_vector","dims":3},"mot":{"type":"match_only_text"},"comp":{"type":"completion"},"tokens":{"type":"token_count","analyzer":"standard"},"half":{"type":"half_float"},"short":{"type":"short"},"byte":{"type":"byte"},"alias_ts":{"type":"alias","path":"@timestamp"},"nested_arr":{"type":"nested","properties":{"k":{"type":"keyword"},"v":{"type":"long"}}},"obj_disabled":{"type":"object","enabled":false},"not_indexed":{"type":"keyword","index":false},"no_docvalues":{"type":"keyword","doc_values":false},"runtime_src":{"type":"keyword"}},"runtime":{"rt_upper":{"type":"keyword","script":{"source":"if (doc['runtime_src'].size()>0) emit(doc['runtime_src'].value.toUpperCase())"}},"rt_error":{"type":"long","script":{"source":"emit(Long.parseLong(doc['runtime_src'].value))"}}}}}
JSON
bulk edge-field-types <<EOF
$I
{"@timestamp":"$NOW","flat":{"a":1,"b":{"c":"deep","d":[1,2]},"e":"str"},"int_range":{"gte":1,"lt":10},"date_range":{"gte":"2024-01-01","lte":"2024-12-31"},"ip_range":"10.0.0.0/8","area":{"type":"polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]},"pt":{"lat":48.85,"lon":2.35},"xy":"1.0,2.0","ver":"1.2.3-beta","wild":"some/long/path/to/a/file.txt","hist":{"values":[0.1,0.5,0.9],"counts":[3,7,23]},"bin":"U29tZSBiaW5hcnk=","vec":[0.1,0.2,0.3],"mot":"match only text","comp":"suggest me","tokens":"count these four tokens","half":1.5,"short":32767,"byte":127,"nested_arr":[{"k":"a","v":1},{"k":"b","v":2}],"obj_disabled":{"anything":"goes","nested":{"deep":true}},"not_indexed":"stored only","no_docvalues":"no dv","runtime_src":"abc"}
$I
{"@timestamp":"$NOW","flat":{"a":"now a string"},"int_range":{"gte":5,"lte":5},"ver":"10.0.0","wild":"another","nested_arr":[],"runtime_src":"42"}
EOF

# --- timestamps --------------------------------------------------------------
log "edge-timestamps"
recreate edge-timestamps <<'JSON'
{"mappings":{"properties":{"@timestamp":{"type":"date","ignore_malformed":true},"nanos":{"type":"date_nanos"},"epoch_ms":{"type":"date","format":"epoch_millis"},"label":{"type":"keyword"}}}}
JSON
bulk edge-timestamps <<EOF
$I
{"label":"epoch zero","@timestamp":"1970-01-01T00:00:00Z","nanos":"1970-01-01T00:00:00.000000001Z","epoch_ms":0}
$I
{"label":"far past","@timestamp":"1900-01-01T00:00:00Z","nanos":"1900-01-01T00:00:00Z","epoch_ms":-2208988800000}
$I
{"label":"far future","@timestamp":"2200-01-01T00:00:00Z","nanos":"2200-01-01T00:00:00Z","epoch_ms":7258118400000}
$I
{"label":"tomorrow","@timestamp":"$TOMORROW"}
$I
{"label":"positive offset","@timestamp":"2024-06-01T12:00:00+14:00"}
$I
{"label":"negative offset","@timestamp":"2024-06-01T12:00:00-12:00"}
$I
{"label":"millis precision","@timestamp":"2024-06-01T12:00:00.123Z"}
$I
{"label":"nanos precision","@timestamp":"2024-06-01T12:00:00.123456789Z","nanos":"2024-06-01T12:00:00.123456789Z"}
$I
{"label":"leap day","@timestamp":"2024-02-29T23:59:59Z"}
$I
{"label":"dst gap (Europe/Berlin)","@timestamp":"2024-03-31T01:30:00Z"}
$I
{"label":"missing timestamp"}
$I
{"label":"null timestamp","@timestamp":null}
$I
{"label":"malformed timestamp (ignored)","@timestamp":"not-a-date"}
$I
{"label":"now","@timestamp":"$NOW"}
EOF

# --- deep nesting ------------------------------------------------------------
log "edge-deep-nesting"
recreate edge-deep-nesting <<'JSON'
{"mappings":{"properties":{"@timestamp":{"type":"date"},"items":{"type":"nested","properties":{"name":{"type":"keyword"},"tags":{"type":"nested","properties":{"t":{"type":"keyword"}}}}}}}}
JSON
DEEP=$(awk 'BEGIN{n=19; for(i=1;i<=n;i++) printf "{\"l%d\":", i; printf "\"bottom\""; for(i=1;i<=n;i++) printf "}"}')
bulk edge-deep-nesting <<EOF
$I
{"@timestamp":"$NOW","deep":$DEEP,"items":[{"name":"a","tags":[{"t":"x"},{"t":"y"}]},{"name":"b","tags":[]}],"matrix":[[1,2],[3,4]]}
EOF

# --- high cardinality --------------------------------------------------------
log "edge-high-cardinality (20,000 docs)"
recreate edge-high-cardinality <<'JSON'
{"mappings":{"properties":{"@timestamp":{"type":"date"},"user_id":{"type":"keyword"},"ip":{"type":"ip"},"session":{"type":"keyword"},"bucket":{"type":"keyword"},"value":{"type":"double"}}}}
JSON
awk -v now="$NOW" 'BEGIN{srand(42); for(i=1;i<=20000;i++){
  printf "{\"index\":{}}\n{\"@timestamp\":\"%s\",\"user_id\":\"user-%07d\",\"ip\":\"%d.%d.%d.%d\",\"session\":\"s-%d-%d\",\"bucket\":\"b%d\",\"value\":%.4f}\n",
  now, i, int(rand()*223)+1, int(rand()*256), int(rand()*256), int(rand()*254)+1, i, int(rand()*1e9), i%50, rand()*1000 }}' | bulk edge-high-cardinality

# --- large documents ---------------------------------------------------------
log "edge-large-docs"
recreate edge-large-docs <<'JSON'
{"mappings":{"properties":{"@timestamp":{"type":"date"},"body":{"type":"text"},"blob":{"type":"keyword","ignore_above":32766},"stack":{"type":"text"}}}}
JSON
BODY=$(awk 'BEGIN{for(i=0;i<12000;i++) printf "lorem%d ipsum ", i}')
STACK=$(awk 'BEGIN{for(i=0;i<400;i++) printf "at com.example.Class%d.method(Class%d.java:%d)\\n", i,i,i}')
BLOB=$(awk 'BEGIN{for(i=0;i<30000;i++) printf "b"}')
bulk edge-large-docs <<EOF
$I
{"@timestamp":"$NOW","body":"$BODY","stack":"java.lang.RuntimeException: boom\\n$STACK"}
$I
{"@timestamp":"$NOW","blob":"$BLOB","body":"short"}
EOF

# --- no timestamp ------------------------------------------------------------
log "edge-no-timestamp"
recreate edge-no-timestamp <<'JSON'
{"mappings":{"properties":{"name":{"type":"keyword"},"score":{"type":"long"},"note":{"type":"text"}}}}
JSON
bulk edge-no-timestamp <<EOF
$I
{"name":"alpha","score":1,"note":"index with no date field"}
$I
{"name":"beta","score":2,"note":"data view must be created without a time field"}
$I
{"name":"gamma","score":3,"note":"useful for ES|QL and Discover without a time picker"}
EOF

log "finished. Suggested data views: edge-*, edge-conflict-*, edge-no-timestamp (no time field)"
