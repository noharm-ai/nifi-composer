#!/bin/bash

# Lembrete para o usuário exportar variáveis se quiser sumir os avisos do Compose
if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
    echo -e "\e[33m[AVISO] Recomenda-se exportar AWS_ACCESS_KEY_ID e AWS_SECRET_ACCESS_KEY para evitar avisos do Docker Compose.\e[0m"
    echo -e "Exemplo: export AWS_ACCESS_KEY_ID=xxxx; export AWS_SECRET_ACCESS_KEY=yyyy"
    echo -e "Ou rode o script assim: AWS_ACCESS_KEY_ID=xxxx AWS_SECRET_ACCESS_KEY=yyyy bash script_integ_02.sh ...\n"
fi

# Definir o caminho absoluto para o arquivo noharm.env
ENV_FILE_PATH="$(pwd)/nifi-composer/noharm.env"

docker_compose_tempfile="docker-compose.temp.yml"

check_status() {
    if [ $? -ne 0 ]; then
        echo "### Erro: $1. O script precisa ser reexecutado."
        exit 1
    fi
}

clone_repository_and_generate_password() {
    echo "### Clonando o repositório e gerando senha para o usuário nifi_noharm..."
    git clone https://github.com/noharm-ai/nifi-composer/ || check_status "Falha ao clonar nifi-composer"
    cd nifi-composer/
    ./update_secrets.sh || check_status "Falha ao executar update_secrets.sh"
    [ ! -f "$ENV_FILE_PATH" ] && { echo "### Erro: noharm.env não encontrado após update_secrets.sh"; exit 1; }
    PASSWORD=$(grep "SINGLE_USER_CREDENTIALS_PASSWORD" "$ENV_FILE_PATH" | cut -d '=' -f2)
    cd ..
}

remove_and_clone_repository() {
    if [ -d "nifi-composer" ]; then
        echo "### Pasta 'nifi-composer' já existe. Tentando remover para garantir nova instalação..."
        sudo rm -rf nifi-composer
        check_status "Falha ao remover a pasta 'nifi-composer'"
    fi
    clone_repository_and_generate_password
}

cleanup_containers() {
    echo "### Parando e removendo containers e volumes..."
    if [ -f "nifi-composer/docker-compose.yml" ]; then
        cd nifi-composer
        docker compose down --volumes --remove-orphans
        check_status "Falha ao parar e remover containers"
        cd ..
    else
        echo "### Erro: docker-compose.yml não encontrado. Certifique-se de que o repositório foi clonado corretamente."
        exit 1
    fi
}

update_env_file() {
    echo "### Atualizando noharm.env..."
    [ ! -f "$ENV_FILE_PATH" ] && { echo "### Erro: noharm.env não encontrado"; exit 1; }
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
    fi
    if [[ "$DB_MULTI_QUERY" =~ \{\} ]]; then
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=\"$DB_MULTI_QUERY\"|" "$ENV_FILE_PATH"
    elif [ -n "$DB_MULTI_QUERY" ]; then
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=SELECT DISTINCT(NOME), FKPESSOA FROM VW_PACIENTES WHERE FKPESSOA IN ($DB_MULTI_QUERY)|" "$ENV_FILE_PATH"
    fi
    echo "### noharm.env atualizado"
}

create_compose_tempfile() {
    echo "### Gerando docker-compose TEMPORÁRIO para a primeira subida do NiFi..."
    cat > "$docker_compose_tempfile" <<EOF
services:
  nifi:
    container_name: "noharm-nifi"
    image: apache/nifi:1.28.0
    privileged: true
    user: root
    entrypoint: ["bash", "-c", "/opt/nifi/scripts/start.sh"]
    env_file:
      - ./nifi-composer/noharm.env
    working_dir: "/opt/nifi/nifi-current"
    ports:
      - "8443:8443/tcp"
    networks:
      - default
    labels:
      maintainer: "NoHarm.ai <suporte@noharm.ai>"
    ipc: "private"
    restart: "no"
networks:
  default:
    driver: bridge
EOF
}

start_nifi_first_run() {
    echo "### Subindo NiFi com compose TEMPORÁRIO (sem volumes externos)..."
    docker compose -f "$docker_compose_tempfile" pull nifi
    docker compose -f "$docker_compose_tempfile" up -d nifi
}

copy_dir_from_container_to_host() {
    echo "### Copiando dados do container para ./nifi-data/"
    mkdir -p nifi-data/{conf,database_repository,flowfile_repository,content_repository,provenance_repository,state,logs}
    for p in conf database_repository flowfile_repository content_repository provenance_repository state logs; do
        docker cp noharm-nifi:/opt/nifi/nifi-current/$p ./nifi-data/$p
    done
    sudo chown -R 1000:1000 ./nifi-data
    sudo chmod -R 700 ./nifi-data
}

remove_temp_compose_and_container() {
    echo "### Removendo NiFi temporário..."
    docker compose -f "$docker_compose_tempfile" down --remove-orphans
    rm -f "$docker_compose_tempfile"
}

install_containers() {
    echo "### Instalando containers com Docker Compose..."
    update_env_file
    docker compose pull
    docker compose up -d
}

install_aws_cli_in_nifi() {
    container_name="noharm-nifi"
    echo "### Instalando AWS CLI no container $container_name..."
    docker exec --user="root" -it "$container_name" apt update
    docker exec --user="root" -it "$container_name" apt install awscli wget -y
    check_status "Falha ao instalar AWS CLI no container $container_name"
}

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

wait_nifi_running() {
    echo "### Aguardando noharm-nifi ficar running..."
    for i in {1..24}; do
        if [ "$(docker inspect -f '{{.State.Running}}' noharm-nifi 2>/dev/null)" == "true" ]; then
            echo "### noharm-nifi está running"; return
        fi
        echo "### Ainda não está running, aguardando 5s..."; sleep 5
    done
    echo "### Erro: noharm-nifi não iniciou"; exit 1
}

generate_and_configure_keys() {
    for attempt in 1 2 3; do
        echo "### Gerando chaves no Nifi (tentativa $attempt)..."
        if docker exec --user=root noharm-nifi /opt/nifi/scripts/ext/genkeypair.sh; then
            echo "### Chaves geradas com sucesso na tentativa $attempt."; break
        fi
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

modify_renew_cert_script() {
    echo "### Modificando renew_cert.sh..."
    c=$(docker ps --format '{{.Names}}' | grep getname)
    [ -z "$c" ] && { echo "### Erro: getname não encontrado"; exit 1; }
    docker exec --user=root "$c" sed -i "s|SSL_URL=.*|SSL_URL=$GETNAME_SSL_URL|" /app/renew_cert.sh || check_status "Erro sed renew_cert"
}

finalize_and_restart_nifi() {
    docker exec --user=root noharm-nifi bash -c 'grep security ./conf/nifi.properties'
    docker restart noharm-nifi || check_status "Erro restart nifi"
}

test_services() {
    echo "### Verificando se o serviço está funcionando para o cliente $CLIENT_NAME com o código de paciente $PATIENT_ID..."
    curl "https://$CLIENT_NAME.getname.noharm.ai/patient-name/$PATIENT_ID"
    check_status "Falha ao verificar o serviço para o cliente $CLIENT_NAME com o código de paciente $PATIENT_ID"
}

main() {
    if [ "$#" -lt 15 ]; then
        echo "### Uso: $0 <REINSTALL_MODE> <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> <GETNAME_SSL_URL> <DB_TYPE> <DB_HOST> <DB_DATABASE> <DB_PORT> <DB_USER> <DB_PASS> <DB_QUERY> <PATIENT_ID> <DB_MULTI_QUERY> <IDS_PATIENT> <CLIENT_NAME> <BRANCH_GIT>"
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
    IDS_PATIENT=${14}
    CLIENT_NAME=${15}
    BRANCH_GIT=${16}

    if [[ "$REINSTALL_MODE" == "true" ]]; then
        remove_and_clone_repository
        cleanup_containers
        update_env_file
        create_compose_tempfile
        start_nifi_first_run
        wait_nifi_running
        copy_dir_from_container_to_host
        remove_temp_compose_and_container
        install_containers
    else
        if [ ! "$(docker ps -q -f name=noharm-nifi)" ]; then
            clone_repository_and_generate_password
            install_containers
        else
            echo "### Container 'noharm-nifi' já está em execução. Pulando a reinstalação."
        fi
    fi

    generate_and_configure_keys
    echo "### Aguardando 1 minuto para garantir que o container noharm-nifi esteja totalmente iniciado..."
    sleep 60
    echo "### Exibindo configurações de segurança do arquivo nifi.properties..."
    docker exec --user="root" -it noharm-nifi /bin/bash -c "cat ./conf/nifi.properties | grep security && exit"
    echo "### Reiniciando o serviço noharm-nifi para aplicar as configurações de segurança..."
    docker restart noharm-nifi
    check_status "Falha ao reiniciar o container noharm-nifi"
    echo "### Reiniciando o serviço noharm-getname para aplicar as modificações do ssl..."
    docker restart noharm-getname
    check_status "Falha ao reiniciar o container noharm-getname"
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
    echo "### Script executado com sucesso!"
}

main "$@"
