#!/bin/bash

# Verificar se o nome do cliente foi passado
if [[ -z "$1" ]]; then
  echo "Erro: Você deve passar o nome do cliente como argumento."
  echo "Uso: bash <(curl https://raw.githubusercontent.com/noharm-ai/nifi-composer/main/nifi_backup_restore.sh) NOME_CLIENTE"
  exit 1
fi

# Variáveis
DOCKER_CONTAINER="noharm-nifi"
NIFI_HOME="/opt/nifi/nifi-current"
CONF_DIR="$NIFI_HOME/conf"
BKUP_DIR="$CONF_DIR/bkp"
AWS_S3_BUCKET="s3://noharm-nifi"
NOME_CLIENTE="$1"

# Executar com root e verificar/instalar nano
echo "Executando como root e verificando instalação do nano..."
docker exec --user="root" -it "$DOCKER_CONTAINER" bash -c "
  if ! command -v nano &> /dev/null; then
    echo 'Nano não está instalado. Instalando...'
    apt-get update && apt-get install nano -y
  else
    echo 'Nano já está instalado.'
  fi
"

# Verificar se o AWS CLI está instalado e instalar caso necessário
docker exec --user="root" -it "$DOCKER_CONTAINER" bash -c "aws --version" &>/dev/null
if [[ $? -ne 0 ]]; then
  echo "AWS CLI não está instalado. Instalando..."
  docker exec --user="root" -it "$DOCKER_CONTAINER" bash -c "
    apt-get update &&
    apt-get install awscli wget unzip -y
  "
  docker restart "$DOCKER_CONTAINER"
  echo "AWS CLI instalado com sucesso."
fi

# Copiar arquivos do S3 para o NiFi
echo "Copiando arquivos do S3..."
docker exec --user="root" -it "$DOCKER_CONTAINER" bash -c "
  aws s3 cp $AWS_S3_BUCKET/$NOME_CLIENTE/backup/conf/flow.json.gz $CONF_DIR/flow.json.gz &&
  aws s3 cp $AWS_S3_BUCKET/$NOME_CLIENTE/backup/conf/flow.xml.gz $CONF_DIR/flow.xml.gz &&
  aws s3 cp $AWS_S3_BUCKET/$NOME_CLIENTE/backup/conf/nifi.properties $BKUP_DIR/nifi.properties
"

# Ajustar permissões dos arquivos copiados
echo "Ajustando permissões dos arquivos copiados..."
docker exec --user="root" -it "$DOCKER_CONTAINER" bash -c "
  chown nifi:nifi $CONF_DIR/flow.json.gz &&
  chown nifi:nifi $CONF_DIR/flow.xml.gz &&
  chown nifi:nifi $BKUP_DIR/nifi.properties &&
  chmod 640 $CONF_DIR/flow.json.gz &&
  chmod 640 $CONF_DIR/flow.xml.gz &&
  chmod 640 $BKUP_DIR/nifi.properties
"

# Substituir valor da propriedade 'nifi.sensitive.props.key'
echo "Substituindo o valor de 'nifi.sensitive.props.key'..."
docker exec --user="root" -it "$DOCKER_CONTAINER" bash -c "
  get_property_value() {
    local prop_key=\"\$1\"
    local prop_file=\"\$2\"
    local prop_value
    prop_value=\$(grep -E \"^\$prop_key=\" \"\$prop_file\" | cut -d'=' -f2)
    echo \"\$prop_value\"
  }

  prop_replace() {
    local prop_key=\"\$1\"
    local new_value=\"\$2\"
    local target_file=\"\$3\"
    sed -i -e \"s|^\$prop_key=.*\$|\$prop_key=\$new_value|\" \"\$target_file\"
  }

  NIFI_PROP_KEY=\$(get_property_value 'nifi.sensitive.props.key' '$CONF_DIR/nifi.properties')
  BKUP_PROP_KEY=\$(get_property_value 'nifi.sensitive.props.key' '$BKUP_DIR/nifi.properties')

  echo \"Valor atual: \$NIFI_PROP_KEY\"
  echo \"Novo valor: \$BKUP_PROP_KEY\"

  prop_replace 'nifi.sensitive.props.key' \"\$BKUP_PROP_KEY\" '$CONF_DIR/nifi.properties'
"

# Reiniciar o serviço
echo "Reiniciando o serviço NiFi..."
docker restart "$DOCKER_CONTAINER"

echo "Processo concluído."