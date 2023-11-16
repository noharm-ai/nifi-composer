#!/bin/bash

# Function to generate a random MD5 string
generate_md5() {
  echo -n "$(date +%s%N | md5sum | head -c 32)"
}

# File path
docker_compose_file_path="./docker-compose.yml"
dot_env_file_path="./noharm.env"

# Generate random MD5 strings
random_md5_SSTrustS=$(generate_md5)
random_md5_SSKeyS=$(generate_md5)

# Sed command to replace values after -P, -K, and -S
sed -i "s/\(-P \)[^ ]*/\1$random_md5_SSTrustS/g; s/\(-K \)[^ ]*/\1$random_md5_SSKeyS/g; s/\(-S \)[^ ]*/\1$random_md5_SSKeyS/g" "$docker_compose_file_path"

# Sed command to replace values in the .env file
sed -i "s/\(KEYSTORE_PASSWORD=\).*/\1$random_md5_SSKeyS/g; s/\(TRUSTSTORE_PASSWORD=\).*/\1$random_md5_SSTrustS/g" "$dot_env_file_path"
