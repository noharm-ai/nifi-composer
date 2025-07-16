#!/bin/bash
# Migração NiFi com sobrescrita segura dos volumes externos

# ---------------------------------------------------------------------------
# Verifica o container
# ---------------------------------------------------------------------------
if ! docker inspect noharm-nifi >/dev/null 2>&1; then
  echo "❌ ERRO: Container 'noharm-nifi' não está rodando"
  echo "Execute este script apenas em ambientes com NiFi já instalado"
  exit 1
fi

# ---------------------------------------------------------------------------
# Prepara estrutura de volumes (sobrescreve se existir)
# ---------------------------------------------------------------------------
echo ">>> Preparando volumes externos em ./nifi-data..."
mkdir -p nifi-data/{conf,database_repository,flowfile_repository,content_repository,provenance_repository,state,logs}
chown -R 1000:1000 nifi-data/

# ---------------------------------------------------------------------------
# Copia os dados do container (com progresso)
# ---------------------------------------------------------------------------
echo ">>> Copiando dados do container para volumes externos..."
docker stop noharm-nifi

declare -a paths=("conf" "database_repository" "flowfile_repository" 
                 "content_repository" "provenance_repository" "state" "logs")
for path in "${paths[@]}"; do
  echo "→ Copiando ${path}..."
  docker cp noharm-nifi:/opt/nifi/nifi-current/${path}/ ./nifi-data/
done

# ---------------------------------------------------------------------------
# Recria o container
# ---------------------------------------------------------------------------
echo ">>> Recriando container com compose down e up..."
set -a
source noharm.env
set +a
docker compose down nifi
docker compose up -d nifi

# ---------------------------------------------------------------------------
# Instalação de pacotes no container
# ---------------------------------------------------------------------------
echo ">>> Instalando utilitários no container..."
docker exec -u root noharm-nifi bash -c "\
  apt-get update && \
  apt-get install -y --no-install-recommends nano vim awscli && \
  rm -rf /var/lib/apt/lists/*"

# ---------------------------------------------------------------------------
# Download das bibliotecas NO CONTAINER (/opt/nifi/nifi-current/lib)
# ---------------------------------------------------------------------------
echo ">>> Instalando bibliotecas no container..."

docker exec -u root noharm-nifi bash -c '\
  cd /opt/nifi/nifi-current/lib && \
  wget -q https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.30/mysql-connector-java-8.0.30.jar && \
  wget -q https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/23.2.0.0/ojdbc8-23.2.0.0.jar && \
  wget -q https://jdbc.postgresql.org/download/postgresql-42.7.3.jar && \
  wget -q https://repo1.maven.org/maven2/org/apache/nifi/nifi-kite-nar/1.15.3/nifi-kite-nar-1.15.3.nar && \
  wget -q https://truststore.pki.rds.amazonaws.com/sa-east-1/sa-east-1-bundle.pem && \
  chown -R nifi:nifi /opt/nifi/nifi-current/lib'

# ---------------------------------------------------------------------------
# Configurações persistentes (sobrescrevendo os arquivos existentes)
# ---------------------------------------------------------------------------
echo ">>> Aplicando configurações nos volumes externos..."

# Timezone (adiciona se não existir)
grep -q "user.timezone" nifi-data/conf/bootstrap.conf || \
  echo "java.arg.8=-Duser.timezone=America/Sao_Paulo" >> nifi-data/conf/bootstrap.conf

# Parâmetros de retenção (sobrescreve)
sed -i 's/^nifi.provenance.repository.max.storage.time=.*/nifi.provenance.repository.max.storage.time=3 days/' nifi-data/conf/nifi.properties
sed -i 's/^nifi.provenance.repository.max.storage.size=.*/nifi.provenance.repository.max.storage.size=1 GB/' nifi-data/conf/nifi.properties

# Cria o arquivo de credenciais no formato específico DENTRO DO CONTAINER
docker exec -u root noharm-nifi bash -c "echo 'accessKey=${AWS_ACCESS_KEY_ID}' > /opt/nifi/nifi-current/aws_credentials && \
echo 'secretKey=${AWS_SECRET_ACCESS_KEY}' >> /opt/nifi/nifi-current/aws_credentials && \
chown nifi:nifi /opt/nifi/nifi-current/aws_credentials && \
chmod 600 /opt/nifi/nifi-current/aws_credentials"

# Configuração adicional do AWS CLI (opcional) DENTRO DO CONTAINER
docker exec -u root noharm-nifi bash -c "mkdir -p /home/nifi/.aws && \
echo -e '[default]\nregion = ${AWS_DEFAULT_REGION:-sa-east-1}\noutput = json' > /home/nifi/.aws/config && \
echo -e '[default]\naws_access_key_id = ${AWS_ACCESS_KEY_ID}\naws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}' > /home/nifi/.aws/credentials && \
chown -R nifi:nifi /home/nifi/.aws && \
chmod -R 700 /home/nifi/.aws"

echo "Configuração AWS concluída com sucesso"

# ---------------------------------------------------------------------------
# Reinicialização final
# ---------------------------------------------------------------------------
echo ">>> Reiniciando o NiFi..."
docker restart noharm-nifi

# ---------------------------------------------------------------------------
# Relatório final
# ---------------------------------------------------------------------------
echo "✅ Migração concluída com sucesso!"
echo "├─ Dados persistidos em: $(pwd)/nifi-data"
echo "├─ Bibliotecas instaladas em: /opt/nifi/nifi-current/lib"
echo "└─ Acesse: https://localhost:8443/nifi"