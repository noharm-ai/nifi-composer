#apt update
#apt install nano vim awscli
wget -c https://truststore.pki.rds.amazonaws.com/sa-east-1/sa-east-1-bundle.pem -P ${NIFI_HOME}/lib
wget -c https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.30/mysql-connector-java-8.0.30.jar -P ${NIFI_HOME}/lib
wget -c https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/23.2.0.0/ojdbc8-23.2.0.0.jar -P ${NIFI_HOME}/lib
wget -c https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/12.6.2.jre11/mssql-jdbc-12.6.2.jre11.jar -P ${NIFI_HOME}/lib
wget -c https://jdbc.postgresql.org/download/postgresql-42.7.3.jar -P ${NIFI_HOME}/lib
wget -c https://repo1.maven.org/maven2/org/apache/nifi/nifi-kite-nar/1.15.3/nifi-kite-nar-1.15.3.nar -P ${NIFI_HOME}/lib
wget -c https://repo1.maven.org/maven2/org/codehaus/jackson/jackson-mapper-asl/1.9.13/jackson-mapper-asl-1.9.13.jar -P ${NIFI_HOME}/lib
echo "java.arg.8=-Duser.timezone=America/Sao_Paulo" >> ${NIFI_HOME}/conf/bootstrap.conf
sed -i 's/^nifi.provenance.repository.max.storage.time=.*/nifi.provenance.repository.max.storage.time=3 days/' ${NIFI_HOME}/conf/nifi.properties
sed -i 's/^nifi.provenance.repository.max.storage.size=.*/nifi.provenance.repository.max.storage.size=1 GB/' ${NIFI_HOME}/conf/nifi.properties
sed -i 's/^nifi.content.repository.archive.max.retention.period=.*/nifi.content.repository.archive.max.retention.period=1 days/' ${NIFI_HOME}/conf/nifi.properties
sed -i 's/^nifi.content.repository.archive.max.usage.percentage=.*/nifi.content.repository.archive.max.usage.percentage=80%/' ${NIFI_HOME}/conf/nifi.properties
