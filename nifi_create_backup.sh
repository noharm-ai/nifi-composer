#!/bin/bash

schema_name=$1  # Captura o primeiro argumento passado pelo bash
echo "Usando schema_name: $schema_name"

mkdir -p /tmp/nifi-upload && \
find /opt/nifi/nifi-current/conf \
    -maxdepth 1 \
    -type f \
    \( -name 'flow.json.gz' -o -name 'flow.xml.gz' -o -name 'nifi.properties' \) \
    -exec cp {} /tmp/nifi-upload/ \; && \
sleep 2 && \
for file in /tmp/nifi-upload/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        aws s3 cp "$file" "s3://noharm-nifi/$schema_name/backup/conf/$filename"
    fi
done && \
rm -rf /tmp/nifi-upload
