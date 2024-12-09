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

# Função para verificar ou solicitar parâmetros
verify_or_request_param() {
  local param_name="$1"
  local param_prompt="$2"

  # Verifica se o parâmetro já existe no arquivo noharm.env
  if ! grep -q "^${param_name}=" "$ENV_FILE"; then
    read -p "$param_prompt: " param_value
    echo "${param_name}=${param_value}" >> "$ENV_FILE"
    echo "$param_name configurado com o valor: $param_value"
  else
    param_value=$(grep "^${param_name}=" "$ENV_FILE" | cut -d'=' -f2-)
    if [ -z "$param_value" ]; then
      read -p "$param_prompt (atualmente vazio): " param_value
      sed -i "s/^${param_name}=.*/${param_name}=${param_value}/" "$ENV_FILE"
      echo "$param_name atualizado com o valor: $param_value"
    fi
  fi

  # Retorna o valor do parâmetro
  echo "$param_value"
}

# Solicitar ou usar parâmetros
NOME_DO_CLIENTE=$(verify_or_request_param "NOME_DO_CLIENTE" "Informe o nome do cliente")
SERVICO_NIFI=$(verify_or_request_param "SERVICO_NIFI" "Informe o nome do serviço do NiFi")
S3_BUCKET_PATH=$(verify_or_request_param "S3_BUCKET_PATH" "Informe o caminho do S3 (ex.: s3://noharm-nifi)")

# Confirmação dos parâmetros
echo "Cliente: $NOME_DO_CLIENTE"
echo "Serviço: $SERVICO_NIFI"
echo "Caminho S3: $S3_BUCKET_PATH"

# Conexão ao contêiner Docker e sincronização
echo "Conectando ao contêiner Docker: $SERVICO_NIFI"
docker exec -i "$SERVICO_NIFI" /bin/bash <<EOF
echo "Dentro do contêiner $SERVICO_NIFI..."

# Caminho local da pasta conf na raiz do contêiner
LOCAL_CONF_DIR="/conf"

# Caminho remoto no S3
S3_CONF_DIR="${S3_BUCKET_PATH}/${NOME_DO_CLIENTE}/conf"

# Verificar se a pasta conf existe
if [ -d "\$LOCAL_CONF_DIR" ]; then
  echo "Sincronizando arquivos..."

  # Sincronizar somente arquivos .json.gz e .xml.gz
  rsync -avz --include="*.json.gz" --include="*.xml.gz" --exclude="*" \
    "\$LOCAL_CONF_DIR/" "\$S3_CONF_DIR/"

  echo "Sincronização concluída."
else
  echo "Pasta conf não encontrada dentro do contêiner."
fi
EOF
