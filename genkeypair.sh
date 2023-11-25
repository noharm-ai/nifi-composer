#!/bin/bash

# Function to extract property value from nifi.properties
get_property_value() {
  local prop_key="$1"
  local prop_file="$2"
  local prop_value
  prop_value=$(grep -E "^$prop_key=" "$prop_file" | cut -d'=' -f2)
  echo "$prop_value"
}

# Function to replce property value from nifi.properties
prop_replace () {
  target_file=${3:-${nifi_props_file}}
  echo "File [${target_file}] replacing [${1}]"
  sed -i -e "s|^$1=.*$|$1=$2|"  ${target_file}
}

#Path to Keytool
KEYTOOL_HOME=$(readlink -f $(which keytool))
echo KEYTOOL_HOME=${KEYTOOL_HOME}

# Paths to NiFi properties file
nifi_props_file=${NIFI_HOME}/conf/nifi.properties

# Extract relevant values from nifi.properties
KEYSTORE_PASSWORD=$(get_property_value "nifi.security.keystorePasswd" "$nifi_props_file")
TRUSTSTORE_PASSWORD=$(get_property_value "nifi.security.truststorePasswd" "$nifi_props_file")
HOSTNAME=$(get_property_value "nifi.remote.input.host" "$nifi_props_file")

echo KEYSTORE_PASSWORD = ${KEYSTORE_PASSWORD}
echo TRUSTSTORE_PASSWORD = ${TRUSTSTORE_PASSWORD}
echo NIFI_HOME = ${NIFI_HOME}
echo HOSTNAME = ${HOSTNAME}

echo Removing Old Files...
[ -f "${NIFI_HOME}/conf/new_keystore.p12" ] && rm ${NIFI_HOME}/conf/new_keystore.p12
[ -f "${NIFI_HOME}/conf/new_truststore.p12" ] && rm ${NIFI_HOME}/conf/new_truststore.p12
[ -f "${NIFI_HOME}/conf/key.pem" ] && rm ${NIFI_HOME}/conf/key.pem
[ -f "${NIFI_HOME}/conf/cert.pem" ] && rm ${NIFI_HOME}/conf/cert.pem
[ -f "${NIFI_HOME}/conf/cert.crt" ] && rm ${NIFI_HOME}/conf/cert.crt

echo Generating New Certificate...
openssl req -x509 -newkey rsa:2048 -keyout ${NIFI_HOME}/conf/key.pem -out ${NIFI_HOME}/conf/cert.pem -days 99999 -subj "/CN=localhost" -addext "subjectAltName = DNS:localhost, DNS:${HOSTNAME}" -addext "basicConstraints = CA:TRUE" -addext "extendedKeyUsage = serverAuth,clientAuth" -addext "keyUsage = digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment,keyAgreement,keyCertSign,cRLSign" -passout pass:${KEYSTORE_PASSWORD}

echo Generating KeyStore...
openssl pkcs12 -export -out ${NIFI_HOME}/conf/new_keystore.p12 -inkey ${NIFI_HOME}/conf/key.pem -in ${NIFI_HOME}/conf/cert.pem -name nifi-key -passin pass:${KEYSTORE_PASSWORD} -passout pass:${KEYSTORE_PASSWORD}

${KEYTOOL_HOME} -v -list -keystore ${NIFI_HOME}/conf/new_keystore.p12 -storepass ${KEYSTORE_PASSWORD}

echo Extracting Certificate...
${KEYTOOL_HOME} -exportcert -keystore ${NIFI_HOME}/conf/new_keystore.p12 -storepass ${KEYSTORE_PASSWORD} -alias nifi-key -rfc -file ${NIFI_HOME}/conf/cert.crt

${KEYTOOL_HOME} -printcert -v -file ${NIFI_HOME}/conf/cert.crt

echo Generating TrustKeyStore...
${KEYTOOL_HOME} -import -file ${NIFI_HOME}/conf/cert.crt -alias nifi-cert -keystore ${NIFI_HOME}/conf/new_truststore.p12 -storetype PKCS12 -keypass ${TRUSTSTORE_PASSWORD} -storepass ${TRUSTSTORE_PASSWORD} -noprompt

${KEYTOOL_HOME} -v -list -keystore ${NIFI_HOME}/conf/new_truststore.p12 -storepass ${TRUSTSTORE_PASSWORD}

[ -f "${NIFI_HOME}/conf/new_keystore.p12" ] && 

# Check if Works
if [ ! -f "${NIFI_HOME}/conf/new_keystore.p12" ]  || [ ! -f "${NIFI_HOME}/conf/new_truststore.p12" ]; then
    echo "Something got wrong"
    exit 1
fi

chown nifi:nifi ${NIFI_HOME}/conf/new_keystore.p12 
chown nifi:nifi ${NIFI_HOME}/conf/new_truststore.p12 

prop_replace 'nifi.security.keystore' "${NIFI_HOME}/conf/new_keystore.p12"
prop_replace 'nifi.security.truststore' "${NIFI_HOME}/conf/new_truststore.p12"

## HOW TO UNDONE IT
## docker cp nifi.properties noharm-nifi:/opt/nifi/nifi-current/conf/nifi.properties
## redo old p12 path
## docker cp noharm-nifi:/opt/nifi/nifi-current/conf/nifi.properties nifi.properties
