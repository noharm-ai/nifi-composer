#!/bin/bash

# Definir o caminho absoluto para o arquivo noharm.env
ENV_FILE_PATH="$(pwd)/nifi-composer/noharm.env"

# Função para verificar o status da execução
check_status() {
    if [ $? -ne 0 ]; then
        echo "### Erro: $1. O script precisa ser reexecutado."
        exit 1
    fi
}

# Função para clonar o repositório e gerar a senha para o usuário nifi_noharm
clone_repository_and_generate_password() {
    echo "### Clonando o repositório e gerando senha para o usuário nifi_noharm..."
    git clone https://github.com/noharm-ai/nifi-composer/
    check_status "Falha ao clonar o repositório 'nifi-composer'"

    cd nifi-composer/
    ./update_secrets.sh
    check_status "Falha ao executar o script 'update_secrets.sh'"

    if [ ! -f "$ENV_FILE_PATH" ]; then
        echo "### Erro: Arquivo noharm.env não foi encontrado após a execução de update_secrets.sh."
        exit 1
    fi

    PASSWORD=$(grep "SINGLE_USER_CREDENTIALS_PASSWORD" "$ENV_FILE_PATH" | cut -d '=' -f2)
    cd ..
}

# Função para remover a pasta "nifi-composer" e recomeçar o processo
remove_and_clone_repository() {
    if [ -d "nifi-composer" ]; then
        echo "### Pasta 'nifi-composer' já existe. Excluindo para garantir nova instalação..."
        sudo rm -rf nifi-composer
        check_status "Falha ao remover a pasta 'nifi-composer'"
    fi

    clone_repository_and_generate_password
    update_env_file
    ln -sf "$ENV_FILE_PATH" nifi-composer/.env
}

# Função para parar e remover containers, redes, volumes, e imagens
cleanup_containers() {
    echo "### Parando e removendo containers e volumes..."
    if [ -f "nifi-composer/docker-compose.yml" ]; then
        cd nifi-composer
        docker compose --env-file noharm.env down --volumes --remove-orphans
        check_status "Falha ao parar e remover containers"
        echo "### Containers removidos com sucesso."
        cd ..
    else
        echo "### Erro: docker-compose.yml não encontrado. Certifique-se de que o repositório foi clonado corretamente."
        exit 1
    fi
}

# Função para realizar o pull de containers com tentativas e espera
retry_docker_pull() {
    retry_count=0
    max_retries=3
    success=false
    sleep_time=30

    while [ $retry_count -lt $max_retries ]; do
        echo "### Tentativa de pull de containers ($((retry_count+1))/$max_retries)..."
        cd nifi-composer
        docker compose --env-file noharm.env up -d
        if [ $? -eq 0 ]; then
            success=true; break
        fi
        echo "### Falha ao fazer pull da imagem, aguardando $sleep_time segundos antes de tentar novamente..."
        sleep $sleep_time
        retry_count=$((retry_count+1))
        sleep_time=$((sleep_time + 30))
        cd ..
    done

    if [ "$success" = false ]; then
        echo "### Erro: Não foi possível fazer pull da imagem após $max_retries tentativas. Verifique sua conexão e tente novamente."
        exit 1
    fi
}

# Função para instalar o AWS CLI no container noharm-nifi
install_aws_cli_in_nifi() {
    container_name="noharm-nifi"
    echo "### Instalando AWS CLI no container $container_name..."
    docker exec --user="root" -it "$container_name" apt update
    docker exec --user="root" -it "$container_name" apt install awscli -y

    docker exec --user=root noharm-nifi bash -c "apt update && apt install wget -y"

    # Ajustar permissões nos arquivos de configuração
    docker exec --user=root noharm-nifi bash -c 'chown nifi:nifi /opt/nifi/nifi-current/conf/bootstrap.conf'

    check_status "Falha ao instalar AWS CLI no container $container_name"
}

# Função para verificar se o AWS CLI está instalado no container noharm-nifi
test_aws_cli_in_nifi() {
    container_name="noharm-nifi"
    echo "### Verificando se o AWS CLI está funcionando dentro do container $container_name..."
    docker exec --user="root" -it "$container_name" /bin/bash -c "aws --version"
    if [ $? -ne 0 ]; then
        echo "### AWS CLI não está instalado no container $container_name. Tentando instalar..."
        install_aws_cli_in_nifi
    else
        echo "### AWS CLI está instalado corretamente no container $container_name."
    fi
}

# Função para testar os serviços configurados
test_services() {
    echo "### Verificando se o serviço está funcionando para o cliente $CLIENT_NAME com o código de paciente $PATIENT_ID..."
    curl "https://$CLIENT_NAME.getname.noharm.ai/patient-name/$PATIENT_ID"
    check_status "Falha ao verificar o serviço para o cliente $CLIENT_NAME com o código de paciente $PATIENT_ID"
}

# Função para atualizar o arquivo de ambiente
update_env_file() {
    echo "### Atualizando variáveis de ambiente no arquivo noharm.env..."
    if [ ! -f "$ENV_FILE_PATH" ]; then
        echo "### Erro: Arquivo noharm.env não encontrado. Verifique a execução de update_secrets.sh."
        exit 1
    fi
    sed -i "s|^AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID|" "$ENV_FILE_PATH"
    sed -i "s|^AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY|" "$ENV_FILE_PATH"
    sed -i "s|^GETNAME_SSL_URL=.*|GETNAME_SSL_URL=$GETNAME_SSL_URL|" "$ENV_FILE_PATH"
    sed -i "s|^DB_TYPE=.*|DB_TYPE=$DB_TYPE|" "$ENV_FILE_PATH"
    sed -i "s|^DB_HOST=.*|DB_HOST=$DB_HOST|" "$ENV_FILE_PATH"
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_DATABASE|" "$ENV_FILE_PATH"
    sed -i "s|^DB_PORT=.*|DB_PORT=$DB_PORT|" "$ENV_FILE_PATH"
    sed -i "s|^DB_USER=.*|DB_USER=$DB_USER|" "$ENV_FILE_PATH"
    sed -i "s|^DB_PASS=.*|DB_PASS=$DB_PASS|" "$ENV_FILE_PATH"
    if [[ "$DB_QUERY" =~ \{\} ]]; then
        sed -i "s|^DB_QUERY=.*|DB_QUERY=\"$DB_QUERY\"|" "$ENV_FILE_PATH"
    elif [ -n "$DB_QUERY" ]; then
        sed -i "s|^DB_QUERY=.*|DB_QUERY=SELECT DISTINCT NOME FROM VW_PACIENTES WHERE FKPESSOA = $DB_QUERY|" "$ENV_FILE_PATH"
    else
        sed -i "s|^DB_QUERY=.*|DB_QUERY=SELECT DISTINCT NOME FROM VW_PACIENTES WHERE FKPESSOA = {}|" "$ENV_FILE_PATH"
    fi
    if [[ "$DB_MULTI_QUERY" =~ \{\} ]]; then
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=\"$DB_MULTI_QUERY\"|" "$ENV_FILE_PATH"
    elif [ -n "$DB_MULTI_QUERY" ]; then
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=SELECT DISTINCT(NOME), FKPESSOA FROM VW_PACIENTES WHERE FKPESSOA IN ($DB_MULTI_QUERY)|" "$ENV_FILE_PATH"
    else
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=SELECT DISTINCT(NOME), FKPESSOA FROM VW_PACIENTES WHERE FKPESSOA IN ({})|" "$ENV_FILE_PATH"
    fi
    echo "### Arquivo noharm.env atualizado com sucesso."  
}

# Função para instalar e iniciar containers
install_containers() {
    echo "### Instalando containers com Docker Compose..."
    update_env_file
    echo "### Iniciando containers com retry..."
    retry_docker_pull
}

# Modificar renew_cert.sh no container getname
modify_renew_cert_script() {
    echo "### Modificando o arquivo renew_cert.sh para usar a variável de ambiente GETNAME_SSL_URL..."
    container_name=$(docker ps --format "{{.Names}}" | grep "getname")
    if [ -z "$container_name" ]; then
        echo "### Erro: Nenhum container com 'getname' no nome foi encontrado."
        exit 1
    fi
    docker exec --user="root" -it "$container_name" sed -i "s|SSL_URL=.*|SSL_URL=${GETNAME_SSL_URL}|" /app/renew_cert.sh
    check_status "Falha ao modificar o script renew_cert.sh no container $container_name"
    echo "### Modificação do renew_cert.sh concluída com sucesso."  
}

# Prepara estrutura de volumes externos
prepare_volumes(){
    echo ">>> Preparando volumes externos em ./nifi-data..."
    mkdir -p nifi-data/{conf,database_repository,flowfile_repository,content_repository,provenance_repository,state,logs}
    chown -R 1000:1000 nifi-data/
    chmod -R 700 nifi-data
}

# Copia dados do container para os volumes externos
copy_dir_containers(){  
    echo ">>> Copiando dados do container para volumes externos..."
    docker stop noharm-nifi
    declare -a paths=("conf" "database_repository" "flowfile_repository"  
                    "content_repository" "provenance_repository" "state" "logs")
    for path in "${paths[@]}"; do
        echo "→ Copiando ${path}..."
        docker cp noharm-nifi:/opt/nifi/nifi-current/${path}/ ./nifi-data/${path}/
    done
}

# Cria credenciais AWS e configura dentro do container
create_credentials_and_configure(){
    export $(grep -E '^AWS_' nifi-composer/noharm.env | xargs)
    docker exec -u root noharm-nifi bash -c "echo 'accessKey=${AWS_ACCESS_KEY_ID}' > /opt/nifi/nifi-current/aws_credentials && \
    echo 'secretKey=${AWS_SECRET_ACCESS_KEY}' >> /opt/nifi/nifi-current/aws_credentials && \
    chown nifi:nifi /opt/nifi/nifi-current/aws_credentials && chmod 600 /opt/nifi/nifi-current/aws_credentials"
    docker exec -u root noharm-nifi bash -c "mkdir -p /home/nifi/.aws && \
    echo -e '[default]\nregion = ${AWS_DEFAULT_REGION:-sa-east-1}\noutput = json' > /home/nifi/.aws/config && \
    echo -e '[default]\naws_access_key_id = ${AWS_ACCESS_KEY_ID}\naws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}' > /home/nifi/.aws/credentials && \
    chown -R nifi:nifi /home/nifi/.aws && chmod -R 700 /home/nifi/.aws"
    echo "Configuração AWS concluída com sucesso"
}

# Espera o container ficar realmente RUNNING, até 12 tentativas de 5s
wait_nifi_running() {
    echo "### Aguardando noharm-nifi ficar running..."
    for i in {1..12}; do
        if [ "$(docker inspect -f '{{.State.Running}}' noharm-nifi)" = "true" ]; then
        echo "### Container iniciado"; return
        fi
        sleep 60
    done
    check_status "noharm-nifi não entrou em Running em tempo"
}

# Agrupa a espera, geração de chave e reinício do getname
generate_and_configure_keys() {
    for attempt in 1 2 3; do
        echo "### Gerando chaves no Nifi (tentativa $attempt)..."
        if docker exec --user=root noharm-nifi /opt/nifi/scripts/ext/genkeypair.sh; then
        echo "### Chaves geradas com sucesso na tentativa $attempt."; break
        fi
        # Em falha de namespace ou procReady, reiniciar e aguardar
        if [ "$attempt" -lt 3 ]; then
        echo "### Falha na tentativa $attempt, reiniciando Nifi e aguardando 15s antes do retry..."
        docker restart noharm-nifi || check_status "Erro reiniciando Nifi na tentativa $attempt"
        wait_nifi_running
        sleep 15
        else
        check_status "Erro genkeypair após 3 tentativas"
        fi
    done

    modify_renew_cert_script
    docker restart noharm-getname || check_status "Erro restart getname"
}

# Exibe configs de segurança e reinicia o Nifi
finalize_and_restart_nifi() {
    docker exec --user=root noharm-nifi bash -c 'grep security ./conf/nifi.properties'
    docker restart noharm-nifi || check_status "Erro restart nifi"
    
}

# Função principal
main() {
    if [ "$#" -lt 14 ]; then
        echo "### Uso: $0 <REINSTALL_MODE> <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> <GETNAME_SSL_URL> <DB_TYPE> <DB_HOST> <DB_DATABASE> <DB_PORT> <DB_USER> <DB_PASS> <DB_QUERY> <PATIENT_ID> <DB_MULTI_QUERY> <CLIENT_NAME>"
        exit 1
    fi

    REINSTALL_MODE=$1
    AWS_ACCESS_KEY_ID=$2
    AWS_SECRET_ACCESS_KEY=$3
    GETNAME_SSL_URL=$4
    DB_TYPE=$5
    DB_HOST=$6
    DB_DATABASE=$7
    DB_PORT=$8
    DB_USER=$9
    DB_PASS=${10}
    DB_QUERY=${11}
    PATIENT_ID=${12}
    DB_MULTI_QUERY=${13}
    CLIENT_NAME=${14}

    if [[ "$REINSTALL_MODE" == "true" ]]; then
        echo "### Modo de reinstalação ativado. Excluindo pasta e reinstalando do zero..."
        remove_and_clone_repository
        cleanup_containers
        install_containers
    else
        echo "### Modo de execução sem reinstalação. Verificando estado atual..."
        if [ ! "$(docker ps -q -f name=noharm-nifi)" ]; then
            echo "### Container 'noharm-nifi' não encontrado. Iniciando containers..."
            clone_repository_and_generate_password
            install_containers
        else
            echo "### Container 'noharm-nifi' já está em execução. Pulando a reinstalação."
        fi
    fi

    # substituído sleep+exec direto por função que aguarda Nifi
    generate_and_configure_keys
    test_aws_cli_in_nifi
    test_services
    finalize_and_restart_nifi

    echo "### Script executado com sucesso!"
    echo "### Senha gerada para o usuário 'nifi_noharm': $PASSWORD"
    echo "### Por favor, coloque essa senha no '1password', com o usuário 'nifi_noharm', dentro da seção 'Nifi server'."

    if [ -f "$ENV_FILE_PATH" ]; then
        echo "### Exibindo o conteúdo do arquivo noharm.env:"
        cat "$ENV_FILE_PATH"
    else
        echo "### Erro: Arquivo noharm.env não encontrado para exibição."
    fi

    echo "### Exibindo configurações de segurança do arquivo nifi.properties..."
    docker exec --user="root" -it noharm-nifi /bin/bash -c "cat ./conf/nifi.properties | grep security && exit"

    echo "### Reiniciando o serviço noharm-nifi para aplicar as configurações de segurança..."
    docker restart noharm-nifi
    check_status "Falha ao reiniciar o container noharm-nifi"

    # Chamadas aos novos métodos
    prepare_volumes
    copy_dir_containers
    create_credentials_and_configure
    docker start noharm-nifi
}

main "$@"
