#!/bin/bash

set -e

# Definir o caminho absoluto para o arquivo noharm.env
ENV_FILE_PATH="$(pwd)/nifi-composer/noharm.env"

# Função para verificar o status da execução
check_status() {
    if [ $? -ne 0 ]; then
        echo "### Erro: $1. O script precisa ser reexecutado."
        exit 1
    fi
}

# Função para remover a pasta nifi-composer com todas as tentativas possíveis
remove_and_clone_repository() {
    if [ -d "nifi-composer" ]; then
        echo "### Pasta 'nifi-composer' já existe. Tentando remover para garantir nova instalação..."
        ls -ld nifi-composer || true

        rm -rf nifi-composer 2>/dev/null || true

        if [ -d "nifi-composer" ]; then
            echo "### Tentando remover com sudo..."
            sudo rm -rf nifi-composer 2>/dev/null || true
        fi

        if [ -d "nifi-composer" ]; then
            echo "### ERRO: Não foi possível remover a pasta 'nifi-composer'."
            echo "### Rode o script como sudo OU remova manualmente:"
            echo "      sudo rm -rf nifi-composer"
            exit 1
        fi
    fi

    clone_repository_and_generate_password
    update_env_file
    ln -sf "$ENV_FILE_PATH" nifi-composer/.env
}

# Função para clonar o repositório e gerar a senha para o usuário nifi_noharm
clone_repository_and_generate_password() {
    echo "### Clonando o repositório e gerando senha para o usuário nifi_noharm..."
    git clone https://github.com/noharm-ai/nifi-composer/ || check_status "Falha ao clonar nifi-composer"

    cd nifi-composer/
    ./update_secrets.sh || check_status "Falha ao executar update_secrets.sh"

    [ ! -f "$ENV_FILE_PATH" ] && { echo "### Erro: noharm.env não encontrado após update_secrets.sh"; exit 1; }
    PASSWORD=$(grep "SINGLE_USER_CREDENTIALS_PASSWORD" "$ENV_FILE_PATH" | cut -d '=' -f2)
    cd ..
}

# Atualiza variáveis no noharm.env
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

# Para e remove containers do ambiente
cleanup_containers() {
    echo "### Parando e removendo containers..."
    cd nifi-composer
    docker compose --env-file noharm.env down --volumes --remove-orphans || check_status "Falha no compose down"
    cd ..
}

# Pull dos containers, com tentativas
retry_docker_pull() {
    for i in 1 2 3; do
        echo "### Pull containers (tentativa $i)..."
        cd nifi-composer
        docker compose --env-file noharm.env up -d && { cd ..; return; }
        cd ..
        sleep $((i * 30))
    done
    echo "### Erro: pull containers falhou"; exit 1
}

wait_nifi_running() {
    echo "### Aguardando noharm-nifi ficar running..."
    for i in {1..12}; do
        if [ "$(docker inspect -f '{{.State.Running}}' noharm-nifi 2>/dev/null)" == "true" ]; then
            echo "### noharm-nifi está running"; return
        fi
        echo "### Ainda não está running, aguardando 5s..."; sleep 5
    done
    echo "### Erro: noharm-nifi não iniciou"; exit 1
}

generate_and_configure_keys() {
    wait_nifi_running
    echo "### Gerando chave no nifi..."
    docker exec --user=root noharm-nifi sh -c /opt/nifi/scripts/ext/genkeypair.sh || check_status "Erro genkeypair"
    modify_renew_cert_script
    docker restart noharm-getname || check_status "Erro restart getname"
}

modify_renew_cert_script() {
    echo "### Modificando renew_cert.sh..."
    c=$(docker ps --format '{{.Names}}' | grep getname)
    [ -z "$c" ] && { echo "### Erro: getname não encontrado"; exit 1; }
    docker exec --user=root "$c" sed -i "s|SSL_URL=.*|SSL_URL=$GETNAME_SSL_URL|" /app/renew_cert.sh || check_status "Erro sed renew_cert"
}

test_aws_cli_in_nifi() {
    echo "### Testando AWS CLI..."
    docker exec --user=root noharm-nifi bash -c 'aws --version' || install_aws_cli_in_nifi
}
install_aws_cli_in_nifi() {
    echo "### Instalando AWS CLI..."
    docker exec --user=root noharm-nifi bash -c 'apt update && apt install awscli wget -y' || check_status "Erro install awscli"
}

test_services() {
    echo "### Testando GetName..."
    curl "https://$CLIENT_NAME.getname.noharm.ai/patient-name/$PATIENT_ID" || check_status "Erro GetName"
}

finalize_and_restart_nifi() {
    echo "### Exibindo security configs..."
    docker exec --user=root noharm-nifi bash -c 'grep security ./conf/nifi.properties'
    echo "### Reiniciando noharm-nifi..."
    docker restart noharm-nifi || check_status "Erro restart nifi"
}

prepare_volumes() {
    echo "### Preparando volumes..."
    mkdir -p nifi-data/{conf,database_repository,flowfile_repository,content_repository,provenance_repository,state,logs}
    chown -R 1000:1000 nifi-data/; chmod -R 700 nifi-data
}
copy_dir_containers() {
    echo "### Copiando dados do container..."
    docker stop noharm-nifi
    for p in conf database_repository flowfile_repository content_repository provenance_repository state logs; do
        docker cp noharm-nifi:/opt/nifi/nifi-current/$p/ nifi-data/$p/
    done
}
create_credentials_and_configure() {
    echo "### Criando credenciais AWS..."
    export $(grep -E '^AWS_' "$ENV_FILE_PATH" | xargs)
    docker exec -u root noharm-nifi bash -c "echo 'accessKey=$AWS_ACCESS_KEY_ID' > /opt/nifi/nifi-current/aws_credentials && echo 'secretKey=$AWS_SECRET_ACCESS_KEY' >> /opt/nifi/nifi-current/aws_credentials && chown nifi:nifi /opt/nifi/nifi-current/aws_credentials && chmod 600 /opt/nifi/nifi-current/aws_credentials"
    docker exec -u root noharm-nifi bash -c "mkdir -p /home/nifi/.aws && echo -e '[default]\nregion=$AWS_DEFAULT_REGION\noutput=json' > /home/nifi/.aws/config && echo -e '[default]\naws_access_key_id=$AWS_ACCESS_KEY_ID\naws_secret_access_key=$AWS_SECRET_ACCESS_KEY' > /home/nifi/.aws/credentials && chown -R nifi:nifi /home/nifi/.aws && chmod -R 700 /home/nifi/.aws"
}

# Função principal
main() {
    [ "$#" -lt 14 ] && { echo "Uso: $0 <REINSTALL_MODE> <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> <GETNAME_SSL_URL> <DB_TYPE> <DB_HOST> <DB_DATABASE> <DB_PORT> <DB_USER> <DB_PASS> <DB_QUERY> <PATIENT_ID> <DB_MULTI_QUERY> <CLIENT_NAME>"; exit 1; }
    REINSTALL_MODE=$1; AWS_ACCESS_KEY_ID=$2; AWS_SECRET_ACCESS_KEY=$3; GETNAME_SSL_URL=$4
    DB_TYPE=$5; DB_HOST=$6; DB_DATABASE=$7; DB_PORT=$8; DB_USER=$9; DB_PASS=${10}
    DB_QUERY=${11}; PATIENT_ID=${12}; DB_MULTI_QUERY=${13}; CLIENT_NAME=${14}

    if [[ "$REINSTALL_MODE" == "true" ]]; then
        remove_and_clone_repository; cleanup_containers; retry_docker_pull
    else
        clone_repository_and_generate_password; retry_docker_pull
    fi

    generate_and_configure_keys; test_aws_cli_in_nifi; test_services; finalize_and_restart_nifi

    echo "### Script concluído. Senha: $PASSWORD"
    cat "$ENV_FILE_PATH"

    prepare_volumes; copy_dir_containers; create_credentials_and_configure; docker start noharm-nifi
}

main "$@"