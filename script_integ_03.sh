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
S3_BUCKET_PATH="https://sa-east-1.console.aws.amazon.com/s3/buckets/noharm-nifi?region=sa-east-1&bucketType=general&tab=objects"
if ! grep -q "^S3_BUCKET_PATH=" "$ENV_FILE"; then
  echo "S3_BUCKET_PATH=$S3_BUCKET_PATH" >> "$ENV_FILE"
fi

# Verificar se o contêiner está ativo
if ! docker ps --format '{{.Names}}' | grep -q "^${SERVICO_NIFI}$"; then
  echo "Erro: O contêiner $SERVICO_NIFI não está em execução."
  exit 1
fi

# Executar comando no contêiner
docker exec -it "$SERVICO_NIFI" bash -c "
if ! command -v rsync &> /dev/null; then
  echo 'Instalando rsync no contêiner...'
  if [ -f /etc/debian_version ]; then
    apt-get update && apt-get install -y rsync || (echo 'Tentando com sudo...' && sudo apt-get update && sudo apt-get install -y rsync)
  elif [ -f /etc/alpine-release ]; then
    apk add --no-cache rsync
  elif [ -f /etc/redhat-release ]; then
    yum install -y rsync
  else
    echo 'Distribuição desconhecida. Não foi possível instalar o rsync.'
    exit 1
  fi
else
  echo 'rsync já está instalado no contêiner.'
fi

LOCAL_CONF_DIR='/conf'
S3_CONF_DIR='${S3_BUCKET_PATH}/${NOME_DO_CLIENTE}/conf'

echo 'Dentro do contêiner $SERVICO_NIFI...'

if [ -d \"\$LOCAL_CONF_DIR\" ]; then
  echo 'Sincronizando arquivos...'
  rsync -avz --include=\"*.json.gz\" --include=\"*.xml.gz\" --exclude=\"*\" \
    \"\$LOCAL_CONF_DIR/\" \"\$S3_CONF_DIR/\"
  echo 'Sincronização concluída.'
else
  echo 'Pasta conf não encontrada dentro do contêiner.'
fi
"
