#!/bin/bash

# Função para verificar ou configurar parâmetros
configure_param() {
  local param_name="$1"
  local param_value="$2"

  if [ -z "$param_value" ]; then
    echo "Erro: $param_name não foi passado como argumento."
    exit 1
  fi

  echo "$param_value"
}

# Leitura de argumentos da linha de comando
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
      echo "Uso: $0 --cliente <NOME_DO_CLIENTE> --servico <SERVICO_NIFI>"
      exit 1
      ;;
  esac
done

# Configurar parâmetros
NOME_DO_CLIENTE=$(configure_param "NOME_DO_CLIENTE" "$NOME_DO_CLIENTE") || exit 1
SERVICO_NIFI=$(configure_param "SERVICO_NIFI" "$SERVICO_NIFI") || exit 1

# Configurar S3_BUCKET_PATH fixo
S3_BUCKET_PATH="s3://noharm-nifi"

# Exibir os valores configurados para depuração
echo "### Cliente: $NOME_DO_CLIENTE"
echo "### Serviço: $SERVICO_NIFI"
echo "### Caminho S3: $S3_BUCKET_PATH"

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
S3_CONF_DIR='${S3_BUCKET_PATH}/${NOME_DO_CLIENTE}/conf/'

echo 'Dentro do contêiner $SERVICO_NIFI...'

if [ -d \"\$LOCAL_CONF_DIR\" ]; then
  echo 'Sincronizando apenas arquivos .xml.gz e .json.gz diretamente na pasta conf...'

  # Filtrar apenas arquivos diretamente na pasta conf (não incluir subdiretórios)
  find \"\$LOCAL_CONF_DIR\" -maxdepth 1 -type f \( -name \"*.json.gz\" -o -name \"*.xml.gz\" \) -exec aws s3 cp {} \"\$S3_CONF_DIR\" \;

  echo 'Sincronização concluída.'
else
  echo 'Pasta conf não encontrada dentro do contêiner.'
fi
"

# Adicionar um crontab para execução automática
CRON_JOB="0 * * * * curl -s https://raw.githubusercontent.com/noharm-ai/nifi-composer/main/script_backup_nifi.sh | bash --cliente $NOME_DO_CLIENTE --servico $SERVICO_NIFI"
(crontab -l 2>/dev/null | grep -v "script_backup_nifi.sh" ; echo "$CRON_JOB") | crontab -
echo "Crontab configurado para executar o script a cada 1 hora."
