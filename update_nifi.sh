#apt update
#apt install nano vim awscli
wget https://truststore.pki.rds.amazonaws.com/sa-east-1/sa-east-1-bundle.pem -P ${NIFI_HOME}/lib
wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.30/mysql-connector-java-8.0.30.jar -P ${NIFI_HOME}/lib
wget https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/23.2.0.0/ojdbc8-23.2.0.0.jar -P ${NIFI_HOME}/lib
wget https://jdbc.postgresql.org/download/postgresql-42.6.0.jar -P ${NIFI_HOME}/lib
wget https://repo1.maven.org/maven2/org/apache/nifi/nifi-kite-nar/1.15.3/nifi-kite-nar-1.15.3.nar -P ${NIFI_HOME}/lib
echo "java.arg.8=-Duser.timezone=America/Sao_Paulo" >> ${NIFI_HOME}/conf/bootstrap.conf
