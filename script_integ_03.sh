#!/bin/bash

# Caminho para o arquivo noharm.env
ENV_FILE="/nifi-composer/noharm.env"

# Função para verificar ou atualizar o parâmetro no arquivo noharm.env
update_or_get_param() {
  local param_name="$1"
  local param_value="$2"

  # Verifica se o parâmetro já existe no arquivo
  if grep -q "^${param_name}=" "$ENV_FILE"; then
    current_value=$(grep "^${param_name}=" "$ENV_FILE" | cut -d'=' -f2-)
    if [ -z "$current_value" ]; then
      sed -i "s/^${param_name}=.*/${param_name}=${param_value}/" "$ENV_FILE"
      echo "$param_name atualizado com o valor: $param_value"
    else
      echo "$current_value"
    fi
  else
    echo "${param_name}=${param_value}" >> "$ENV_FILE"
    echo "$param_name adicionado ao arquivo com o valor: $param_value"
  fi
}

# Solicita ou utiliza o nome do cliente
if ! grep -q "^NOME_DO_CLIENTE=" "$ENV_FILE"; then
  read -p "Informe o nome do cliente: " NOME_DO_CLIENTE
  echo "NOME_DO_CLIENTE=${NOME_DO_CLIENTE}" >> "$ENV_FILE"
else
  NOME_DO_CLIENTE=$(grep "^NOME_DO_CLIENTE=" "$ENV_FILE" | cut -d'=' -f2-)
fi

# Solicita ou utiliza o nome do serviço
if ! grep -q "^SERVICO_NIFI=" "$ENV_FILE"; then
  read -p "Informe o nome do serviço do NiFi: " SERVICO_NIFI
  echo "SERVICO_NIFI=${SERVICO_NIFI}" >> "$ENV_FILE"
else
  SERVICO_NIFI=$(grep "^SERVICO_NIFI=" "$ENV_FILE" | cut -d'=' -f2-)
fi

# Solicita ou utiliza o caminho do S3
if ! grep -q "^S3_BUCKET_PATH=" "$ENV_FILE"; then
  read -p "Informe o caminho do S3 (ex.: s3://noharm-nifi): " S3_BUCKET_PATH
  echo "S3_BUCKET_PATH=${S3_BUCKET_PATH}" >> "$ENV_FILE"
else
  S3_BUCKET_PATH=$(grep "^S3_BUCKET_PATH=" "$ENV_FILE" | cut -d'=' -f2-)
fi

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