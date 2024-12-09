#!/bin/bash

# Caminho para o diretório base
BASE_DIR="/nifi-composer"
SCRIPT_DIR="$BASE_DIR/nifi-scripts"

# Garantir que a pasta nifi-scripts exista
if [ ! -d "$SCRIPT_DIR" ]; then
  echo "Criando o diretório $SCRIPT_DIR..."
  mkdir -p "$SCRIPT_DIR"
  chmod 755 "$SCRIPT_DIR"
fi

# Caminho para o arquivo noharm.env
ENV_FILE="$BASE_DIR/noharm.env"

# Função para verificar ou configurar parâmetros
configure_param() {
  local param_name="$1"
  local param_value="$2"

  if [ -n "$param_value" ]; then
    if ! grep -q "^${param_name}=" "$ENV_FILE"; then
      echo "$param_name=$param_value" >> "$ENV_FILE"
    fi
  else
    if grep -q "^${param_name}=" "$ENV_FILE"; then
      param_value=$(grep "^${param_name}=" "$ENV_FILE" | cut -d'=' -f2-)
    else
      echo "Erro: $param_name não foi passado e não está configurado no $ENV_FILE."
      exit 1
    fi
  fi

  echo "$param_value"
}

# Configurar parâmetros
NOME_DO_CLIENTE=$(configure_param "NOME_DO_CLIENTE" "$NOME_DO_CLIENTE")
SERVICO_NIFI=$(configure_param "SERVICO_NIFI" "$SERVICO_NIFI")

# Configurar S3_BUCKET_PATH fixo
S3_BUCKET_PATH="s3://noharm-nifi"
if ! grep -q "^S3_BUCKET_PATH=" "$ENV_FILE"; then
  echo "S3_BUCKET_PATH=$S3_BUCKET_PATH" >> "$ENV_FILE"
fi

# Configurar credenciais AWS
export AWS_ACCESS_KEY_ID=$(grep "^AWS_ACCESS_KEY_ID=" "$ENV_FILE" | cut -d'=' -f2-)
export AWS_SECRET_ACCESS_KEY=$(grep "^AWS_SECRET_ACCESS_KEY=" "$ENV_FILE" | cut -d'=' -f2-)
export AWS_DEFAULT_REGION=$(grep "^AWS_DEFAULT_REGION=" "$ENV_FILE" | cut -d'=' -f2-)

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_DEFAULT_REGION" ]; then
  echo "Erro: Credenciais AWS não configuradas no arquivo $ENV_FILE."
  exit 1
fi

# Verificar se o contêiner existe antes de executar o comando
echo "Verificando se o contêiner '$SERVICO_NIFI' está ativo..."
if ! docker ps --format '{{.Names}}' | grep -q "^${SERVICO_NIFI}$"; then
  echo "Erro: O contêiner $SERVICO_NIFI não está em execução."
  echo "Contêineres ativos no momento:"
  docker ps --format '{{.Names}}'
  exit 1
fi

# Exibir o comando que será executado
echo "Comando a ser executado:"
echo "docker exec -it \"$SERVICO_NIFI\" bash -c \"...\""

# Executar comando no contêiner
docker exec -it "$SERVICO_NIFI" bash -c "
LOCAL_CONF_DIR='/opt/nifi/nifi-current/conf'
S3_CONF_DIR='${S3_BUCKET_PATH}/${NOME_DO_CLIENTE}/conf'

echo 'Dentro do contêiner $SERVICO_NIFI...'

if [ -d \"\$LOCAL_CONF_DIR\" ]; then
  echo 'Sincronizando arquivos com AWS CLI...'
  
  # Enviar arquivos para o S3
  aws s3 cp \"\$LOCAL_CONF_DIR\" \"\$S3_CONF_DIR\" --recursive --exclude \"*\" --include \"*.json.gz\" --include \"*.xml.gz\"
  
  echo 'Sincronização concluída.'
else
  echo 'Pasta conf não encontrada dentro do contêiner.'
fi
"
