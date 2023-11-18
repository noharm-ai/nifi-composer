#!/bin/bash

# Function to extract property value from nifi.properties
get_property_value() {
  local prop_key="$1"
  local prop_file="$2"
  local prop_value
  prop_value=$(grep -E "^$prop_key=" "$prop_file" | cut -d'=' -f2)
  echo "$prop_value"
}

# Paths to NiFi properties file
nifi_properties_file=${NIFI_HOME}/conf/nifi.properties

# Extract relevant values from nifi.properties
KEYSTORE_PASSWORD=$(get_property_value "nifi.security.keystorePasswd" "$nifi_properties_file")
TRUSTSTORE_PASSWORD=$(get_property_value "nifi.security.truststorePasswd" "$nifi_properties_file")

echo KEYSTORE_PASSWORD = ${KEYSTORE_PASSWORD}
echo TRUSTSTORE_PASSWORD = ${TRUSTSTORE_PASSWORD}

echo Generating KeyStore...
rm ${NIFI_HOME}/conf/new_keystore.p12
rm ${NIFI_HOME}/conf/key.pem
rm ${NIFI_HOME}/conf/cert.pem

#openssl req -x509 -newkey rsa:2048 -keyout ${NIFI_HOME}/conf/key.pem -out ${NIFI_HOME}/conf/cert.pem -days 60 -subj "/CN=localhost" -addext "subjectAltName = DNS:localhost, DNS:noharm-nifi" -addext "basicConstraints = CA:TRUE" -addext "extendedKeyUsage = serverAuth,clientAuth" -addext "keyUsage = digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment,keyAgreement,keyCertSign,cRLSign" -passout pass:${KEYSTORE_PASSWORD}

#openssl pkcs12 -export -out ${NIFI_HOME}/conf/new_keystore.p12 -inkey ${NIFI_HOME}/conf/key.pem -in ${NIFI_HOME}/conf/cert.pem -name nifi-key -passin pass:${KEYSTORE_PASSWORD} -passout pass:${KEYSTORE_PASSWORD}

/opt/java/openjdk/bin/keytool -genkeypair -keystore ${NIFI_HOME}/conf/new_keystore.p12 -storetype PKCS12 -storepass ${KEYSTORE_PASSWORD} -alias nifi-key -keyalg RSA -keysize 2048 -validity 99999 -dname "CN=localhost" -ext san=dns:localhost,dns:noharm-nifi -ext bc=ca:true -ext eku=serverAuth,clientAuth -ext ku=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment,keyAgreement,keyCertSign,cRLSign

/opt/java/openjdk/bin/keytool -v -list -keystore ${NIFI_HOME}/conf/new_keystore.p12 -storepass ${KEYSTORE_PASSWORD}

echo Extracting Certificate...
/opt/java/openjdk/bin/keytool -exportcert -keystore ${NIFI_HOME}/conf/keystore.p12 -storepass ${KEYSTORE_PASSWORD} -alias nifi-key -rfc -file ${NIFI_HOME}/conf/cert.crt

/opt/java/openjdk/bin/keytool -printcert -v -file ${NIFI_HOME}/conf/cert.crt

/opt/java/openjdk/bin/keytool -importcert -file ${NIFI_HOME}/conf/cert.crt -alias nifi-new-key -keystore ${NIFI_HOME}/conf/new_keystore.p12 -storetype PKCS12 -storepass ${KEYSTORE_PASSWORD} -noprompt

/opt/java/openjdk/bin/keytool -v -list -keystore ${NIFI_HOME}/conf/new_keystore.p12 -storepass ${KEYSTORE_PASSWORD}

echo Generating TrustKeyStore...
rm ${NIFI_HOME}/conf/new_truststore.p12
/opt/java/openjdk/bin/keytool -import -file ${NIFI_HOME}/conf/cert.crt -alias nifi-cert -keystore ${NIFI_HOME}/conf/new_truststore.p12 -storetype PKCS12 -keypass ${TRUSTSTORE_PASSWORD} -storepass ${TRUSTSTORE_PASSWORD} -noprompt

/opt/java/openjdk/bin/keytool -v -list -keystore ${NIFI_HOME}/conf/new_truststore.p12 -storepass ${TRUSTSTORE_PASSWORD}
