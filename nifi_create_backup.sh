#!/bin/bash

schema_name=$1  # Captura o primeiro argumento passado pelo bash
echo "Usando schema_name: $schema_name"

mkdir -p /tmp/nifi-upload && \
find /opt/nifi/nifi-current/conf -maxdepth 1 -type f \( -name 'flow.json.gz' -o -name 'flow.xml.gz' -o -name 'nifi.properties' \) -exec cp {} /tmp/nifi-upload/ \; && \
sleep 2 && \
aws s3 sync /tmp/nifi-upload s3://noharm-nifi/$schema_name/backup/conf --exclude '*' --include '*.json.gz' --include '*.xml.gz' --include 'nifi.properties' && \
rm -rf /tmp/nifi-upload