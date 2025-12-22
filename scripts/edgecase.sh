#!/bin/sh
# A script to install edge case data for Kibana testing with configurable fields across multiple indices

username="elastic"
password="changeme"
elasticsearch_url="http://localhost:9200"  # replace with your Elasticsearch URL if different
index_base_name="testhuge"
total_fields=50000          # Total number of fields to create across all indices
fields_per_index=5000       # Number of fields per index (optimized for performance)
records_per_index=2         # Number of records per index

# Calculate number of indices needed
num_indices=$((total_fields / fields_per_index))

# Helper function to get field type by index (cycles through 7 types)
get_field_type() {
    type_idx=$(($1 % 7))
    case $type_idx in
        0) echo "keyword" ;;
        1) echo "text" ;;
        2) echo "long" ;;
        3) echo "double" ;;
        4) echo "boolean" ;;
        5) echo "date" ;;
        6) echo "ip" ;;
    esac
}

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

# Function to generate mapping with specified number of fields
generate_mapping() {
    local num_fields=$1
    local index_num=$2
    
    # Calculate field offset for this index to ensure unique field names
    local field_offset=$(((index_num - 1) * fields_per_index))
    
    # Start the mapping JSON
    mapping='{
        "settings": {
            "index": {
                "number_of_shards": 1,
                "number_of_replicas": 0,
                "mapping": {
                    "total_fields": {
                        "limit": '$((num_fields + 1000))'
                    }
                }
            }
        },
        "mappings": {
            "properties": {
                "@timestamp": {"type": "date"},
                "message": {"type": "text"},
                "level": {"type": "keyword"},'
    
    # Generate regular fields with unique names across all indices
    # Subtract 3 to account for the base fields: @timestamp, message, level
    i=1
    while [ $i -le $((num_fields - 3)) ]; do
        global_field_num=$((field_offset + i))
        field_name=$(printf "field_%06d" $global_field_num)
        field_type=$(get_field_type $i)
        
        mapping="${mapping}\"${field_name}\": {\"type\": \"${field_type}\"},"
        
        # Add some nested objects every 1000 fields for variety
        if [ $((i % 1000)) -eq 0 ]; then
            nested_name="nested_object_${index_num}_$((i/1000))"
            mapping="${mapping}\"${nested_name}\": {
                \"type\": \"nested\",
                \"properties\": {
                    \"nested_field_001\": {\"type\": \"keyword\"},
                    \"nested_field_002\": {\"type\": \"text\"},
                    \"nested_field_003\": {\"type\": \"long\"}
                }
            },"
        fi
        i=$((i + 1))
    done
    
    # Add geo_point and final nested object
    mapping="${mapping}\"geo_location\": {\"type\": \"geo_point\"},
                \"final_nested\": {
                    \"type\": \"nested\",
                    \"properties\": {
                        \"final_field_001\": {\"type\": \"keyword\"},
                        \"final_field_002\": {\"type\": \"text\"}
                    }
                }"
    
    # Close the mapping JSON
    mapping="${mapping}}
        }
    }"
    
    echo "$mapping"
}

# Function to generate a single document with edge case data
generate_document() {
    doc_id=$1
    num_fields=$2
    doc_type=$3  # 1=normal, 2=nulls/empty, 3=extreme
    index_num=$4
    
    # Calculate field offset for this index to ensure unique field names
    field_offset=$(((index_num - 1) * fields_per_index))
    
    # Start the document
    doc="{\"@timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")\",
               \"message\": \"Generated edge case test document ${doc_id}\",
               \"level\": \""
    
    case $doc_type in
        1) doc="${doc}info\"," ;;
        2) doc="${doc}warn\"," ;;
        3) doc="${doc}error\"," ;;
    esac
    
    # Generate field data based on document type with unique field names
    # Subtract 3 to account for the base fields: @timestamp, message, level
    i=1
    while [ $i -le $((num_fields - 3)) ]; do
        global_field_num=$((field_offset + i))
        field_name=$(printf "field_%06d" $global_field_num)
        field_type=$(get_field_type $i)
        
        doc="${doc}\"${field_name}\": "
        
        case $doc_type in
            1) # Normal values
                case $field_type in
                    "keyword") doc="${doc}\"value_${i}\"" ;;
                    "text") doc="${doc}\"This is text content for field ${i}\"" ;;
                    "long") doc="${doc}$((i * 100))" ;;
                    "double") doc="${doc}$((i * 100)).$((i % 100))" ;;
                    "boolean") 
                        if [ $((i % 2)) -eq 0 ]; then
                            doc="${doc}true"
                        else
                            doc="${doc}false"
                        fi
                        ;;
                    "date") doc="${doc}\"2024-01-01T12:$(printf "%02d" $((i % 60))):00.000Z\"" ;;
                    "ip") doc="${doc}\"192.168.$((i % 255)).$((i % 255))\"" ;;
                esac
                ;;
            2) # Null and empty values
                case $field_type in
                    "keyword") 
                        if [ $((i % 3)) -eq 0 ]; then
                            doc="${doc}null"
                        else
                            doc="${doc}\"\""
                        fi
                        ;;
                    "text") 
                        if [ $((i % 3)) -eq 0 ]; then
                            doc="${doc}null"
                        else
                            doc="${doc}\"\""
                        fi
                        ;;
                    "long") 
                        if [ $((i % 3)) -eq 0 ]; then
                            doc="${doc}null"
                        else
                            doc="${doc}0"
                        fi
                        ;;
                    "double") 
                        if [ $((i % 3)) -eq 0 ]; then
                            doc="${doc}null"
                        else
                            doc="${doc}0.0"
                        fi
                        ;;
                    "boolean") 
                        if [ $((i % 3)) -eq 0 ]; then
                            doc="${doc}null"
                        else
                            doc="${doc}false"
                        fi
                        ;;
                    "date") 
                        if [ $((i % 3)) -eq 0 ]; then
                            doc="${doc}null"
                        else
                            doc="${doc}\"1970-01-01T00:00:00.000Z\""
                        fi
                        ;;
                    "ip") 
                        if [ $((i % 3)) -eq 0 ]; then
                            doc="${doc}null"
                        else
                            doc="${doc}\"0.0.0.0\""
                        fi
                        ;;
                esac
                ;;
            3) # Extreme values
                case $field_type in
                    "keyword") doc="${doc}\"very_long_keyword_value_that_might_cause_issues_field_${i}_with_unicode_你好世界_and_special_chars_!@#\$%\"" ;;
                    "text") doc="${doc}\"Extremely long text field ${i} with lots of content and unicode characters: 🌍 🚀 ñáéíóú and JSON escapes: {\\\"test\\\": true}\"" ;;
                    "long") 
                        if [ $((i % 2)) -eq 0 ]; then
                            doc="${doc}9223372036854775807"
                        else
                            doc="${doc}-9223372036854775808"
                        fi
                        ;;
                    "double") 
                        if [ $((i % 2)) -eq 0 ]; then
                            doc="${doc}1.7976931348623157E308"
                        else
                            doc="${doc}-1.7976931348623157E308"
                        fi
                        ;;
                    "boolean") doc="${doc}true" ;;
                    "date") 
                        if [ $((i % 2)) -eq 0 ]; then
                            doc="${doc}\"2024-12-31T23:59:59.999Z\""
                        else
                            doc="${doc}\"1970-01-01T00:00:00.000Z\""
                        fi
                        ;;
                    "ip") doc="${doc}\"255.255.255.255\"" ;;
                esac
                ;;
        esac
        
        doc="${doc},"
        
        # Add nested objects every 1000 fields
        if [ $((i % 1000)) -eq 0 ]; then
            nested_name="nested_object_${index_num}_$((i/1000))"
            doc="${doc}\"${nested_name}\": {"
            case $doc_type in
                1) doc="${doc}\"nested_field_001\": \"nested_value_${i}\", \"nested_field_002\": \"Nested text ${i}\", \"nested_field_003\": $((i * 10))" ;;
                2) doc="${doc}\"nested_field_001\": null, \"nested_field_002\": \"\", \"nested_field_003\": 0" ;;
                3) doc="${doc}\"nested_field_001\": \"NESTED_MAX_${i}\", \"nested_field_002\": \"Extreme nested content\", \"nested_field_003\": 999999999" ;;
            esac
            doc="${doc}},"
        fi
        i=$((i + 1))
    done
    
    # Add final geo_location and nested object
    case $doc_type in
        1) doc="${doc}\"geo_location\": {\"lat\": 40.7128, \"lon\": -74.0060}," ;;
        2) doc="${doc}\"geo_location\": {\"lat\": 0.0, \"lon\": 0.0}," ;;
        3) doc="${doc}\"geo_location\": {\"lat\": 90.0, \"lon\": 180.0}," ;;
    esac
    
    doc="${doc}\"final_nested\": {"
    case $doc_type in
        1) doc="${doc}\"final_field_001\": \"final_value\", \"final_field_002\": \"Final text content\"" ;;
        2) doc="${doc}\"final_field_001\": null, \"final_field_002\": \"\"" ;;
        3) doc="${doc}\"final_field_001\": \"FINAL_EXTREME_VALUE\", \"final_field_002\": \"Final extreme content with unicode 🎯\"" ;;
    esac
    doc="${doc}}"
    
    doc="${doc}}"
    echo "$doc"
}

# Delete existing indices if they exist
echo "Cleaning up existing indices..."
idx=1
while [ $idx -le $num_indices ]; do
    current_index="${index_base_name}_${idx}"
    curl -s -u "${username}:${password}" -X DELETE "${elasticsearch_url}/${current_index}" -H 'Content-Type: application/json' > /dev/null 2>&1
    idx=$((idx + 1))
done

echo "Creating $num_indices indices with $fields_per_index fields each (total: $total_fields fields)..."

# Create each index with mapping and documents
idx=1
while [ $idx -le $num_indices ]; do
    current_index="${index_base_name}_${idx}"
    echo "Processing index $idx/$num_indices: $current_index"
    
    # Generate and create mapping
    echo "  Creating mapping with $fields_per_index fields..."
    mapping_response=$(generate_mapping $fields_per_index $idx | curl -s -u "${username}:${password}" -X PUT "${elasticsearch_url}/${current_index}" -H 'Content-Type: application/json' --data-binary @-)
    if [ $? -ne 0 ]; then
        echo "  Failed to create index mapping for $current_index."
        echo "  Error response from Elasticsearch:"
        echo "$mapping_response"
        exit 1
    fi
    
    echo "  Index $current_index created successfully."
    
    # Generate and insert documents for this index
    echo "  Generating and inserting $records_per_index documents..."
    i=1
    while [ $i -le $records_per_index ]; do
        # Determine document type based on ID for variety
        doc_type=1
        if [ $((i % 3)) -eq 2 ]; then
            doc_type=2  # null/empty values
        elif [ $((i % 3)) -eq 0 ]; then
            doc_type=3  # extreme values
        fi
        
        # Generate document
        
        # Insert document and check for errors
        http_code=$(generate_document "${idx}_${i}" $fields_per_index $doc_type $idx | curl -s -o /dev/null -w "%{http_code}" -u "${username}:${password}" -X POST "${elasticsearch_url}/${current_index}/_doc/${i}" -H 'Content-Type: application/json' --data-binary @-)
        if [ "$http_code" -ne 201 ] && [ "$http_code" -ne 200 ]; then
            echo "    ERROR: Failed to insert document ${i} into index ${current_index} (HTTP status: $http_code)"
            # Optionally, exit on error. Uncomment the next line to stop on first failure.
            # exit 1
        fi
        
        if [ $((i % 25)) -eq 0 ]; then
            echo "    Inserted $i/$records_per_index documents..."
        fi
        i=$((i + 1))
    done
    
    echo "  Completed index $current_index with $records_per_index documents."
    idx=$((idx + 1))
done

echo "Edge case data installation complete!"
echo "Created $num_indices indices (${index_base_name}_1 to ${index_base_name}_${num_indices})"
echo "Each index has $fields_per_index unique fields and $records_per_index documents"
echo "Total: $total_fields unique fields across $((num_indices * records_per_index)) documents"