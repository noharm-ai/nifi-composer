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

  # Se o valor foi passado por argumento, configurá-lo
  if [ -n "$param_value" ]; then
    echo "$param_name=$param_value" >> "$ENV_FILE"
    echo "$param_name configurado com o valor: $param_value"
  else
    # Caso contrário, buscar no arquivo noharm.env
    if grep -q "^${param_name}=" "$ENV_FILE"; then
      param_value=$(grep "^${param_name}=" "$ENV_FILE" | cut -d'=' -f2-)
    else
      echo "Erro: $param_name não foi passado e não está configurado no $ENV_FILE."
      exit 1
    fi
  fi

  # Retorna o valor do parâmetro
  echo "$param_value"
}

# Valores padrão
NOME_DO_CLIENTE=""
SERVICO_NIFI=""

# Leitura de argumentos de linha de comando
while [[ $# -gt 0 ]]; do
  case $1 in
    --cliente)
      NOME_DO_CLIENTE="$2"
      shift 2
      ;;
    --servico)
      SERVICO_NIFI="$2"
      shift 2
      ;;
    *)
      echo "Uso: $0 [--cliente NOME_DO_CLIENTE] [--servico SERVICO_NIFI]"
      exit 1
      ;;
  esac
done

# Configurar parâmetros
NOME_DO_CLIENTE=$(configure_param "NOME_DO_CLIENTE" "$NOME_DO_CLIENTE")
SERVICO_NIFI=$(configure_param "SERVICO_NIFI" "$SERVICO_NIFI")

# Configurar S3_BUCKET_PATH fixo
S3_BUCKET_PATH="https://sa-east-1.console.aws.amazon.com/s3/buckets/noharm-nifi?region=sa-east-1&bucketType=general&tab=objects"
echo "S3_BUCKET_PATH está fixado como: $S3_BUCKET_PATH"

# Atualizar o valor no arquivo noharm.env
if grep -q "^S3_BUCKET_PATH=" "$ENV_FILE"; then
  sed -i "s|^S3_BUCKET_PATH=.*|S3_BUCKET_PATH=$S3_BUCKET_PATH|" "$ENV_FILE"
else
  echo "S3_BUCKET_PATH=$S3_BUCKET_PATH" >> "$ENV_FILE"
fi

# Confirmação dos parâmetros
echo "Cliente: $NOME_DO_CLIENTE"
echo "Serviço: $SERVICO_NIFI"
echo "Caminho S3: $S3_BUCKET_PATH"

# Conexão ao contêiner Docker e sincronização
echo "Conectando ao contêiner Docker: $SERVICO_NIFI"

# Use valores diretamente no docker exec para evitar substituições incorretas
docker exec -it "$SERVICO_NIFI" bash -c "
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