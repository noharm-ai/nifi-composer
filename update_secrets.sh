#!/bin/bash

# Function to generate a random MD5 string
generate_md5() {
  echo -n "$(date +%s%N | md5sum | head -c 32)"
}

# File path
dot_env_file_path="./noharm.env"

# Generate random MD5 strings
random_md5_SPassS=$(generate_md5)
random_md5_SPassS=$(echo $random_md5_SPassS | head -c 15)

# Sed command to replace values in the .env file
sed -i "s/\(SINGLE_USER_CREDENTIALS_PASSWORD=\).*/\1$random_md5_SPassS/g" "$dot_env_file_path"
