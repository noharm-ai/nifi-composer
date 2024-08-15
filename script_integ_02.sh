#!/bin/bash

test_docker() {
    echo "Testando instalação do Docker..."
    if ! docker ps > /dev/null 2>&1; then
        echo "Docker não está rodando, iniciando serviço..."
        sudo systemctl start docker
    fi
    docker ps
    echo "Docker está funcionando corretamente."
}

update_env_file() {
    echo "Atualizando variáveis de ambiente no arquivo noharm.env..."

    # Atualiza somente as variáveis passadas como argumento
    [ -n "$AWS_ACCESS_KEY_ID" ] && sed -i "s|^AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID|" noharm.env
    [ -n "$AWS_SECRET_ACCESS_KEY" ] && sed -i "s|^AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY|" noharm.env
    [ -n "$GETNAME_SSL_URL" ] && sed -i "s|^GETNAME_SSL_URL=.*|GETNAME_SSL_URL=$GETNAME_SSL_URL|" noharm.env
    [ -n "$DB_TYPE" ] && sed -i "s|^DB_TYPE=.*|DB_TYPE=$DB_TYPE|" noharm.env
    [ -n "$DB_HOST" ] && sed -i "s|^DB_HOST=.*|DB_HOST=$DB_HOST|" noharm.env
    [ -n "$DB_DATABASE" ] && sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_DATABASE|" noharm.env
    [ -n "$DB_PORT" ] && sed -i "s|^DB_PORT=.*|DB_PORT=$DB_PORT|" noharm.env
    [ -n "$DB_USER" ] && sed -i "s|^DB_USER=.*|DB_USER=$DB_USER|" noharm.env
    [ -n "$DB_PASS" ] && sed -i "s|^DB_PASS=.*|DB_PASS=$DB_PASS|" noharm.env
    [ -n "$DB_QUERY" ] && sed -i "s|^DB_QUERY=.*|DB_QUERY=$DB_QUERY|" noharm.env
    [ -n "$DB_MULTI_QUERY" ] && sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=$DB_MULTI_QUERY|" noharm.env

    echo "Arquivo noharm.env atualizado com sucesso."
}

generate_password() {
    echo "Gerando senha para o usuário nifi_noharm..."
    cd nifi-composer/

    # Executa o script para gerar e substituir a senha
    ./update_secrets.sh

    echo "Senha gerada e aplicada no arquivo noharm.env."
}

install_containers() {
    echo "Instalando containers com Docker Compose..."
    git clone https://github.com/noharm-ai/nifi-composer/
    cd nifi-composer/
    ./update_secrets.sh

    update_env_file

    echo "Iniciando containers..."
    docker compose up -d

    echo "Aguardando containers iniciarem..."
    sleep 20  # Pode ajustar o tempo conforme necessário

    echo "Verificando status dos containers..."
    docker ps

    echo "Configurando o container noharm-nifi..."
    docker exec --user="root" -t noharm-nifi sh -c /opt/nifi/scripts/ext/genkeypair.sh

    echo "Atualizando o container noharm-nifi e instalando pacotes adicionais..."
    docker exec --user="root" -it noharm-nifi apt update
    docker exec --user="root" -it noharm-nifi apt install nano vim awscli -y
    docker restart noharm-nifi
}

test_services() {
    echo "Verificando se o AWS CLI está funcionando dentro do container..."
    docker exec --user="root" -it noharm-nifi /bin/bash -c "aws s3 ls && exit"

    echo "Verificando se o serviço está funcionando para o cliente $CLIENT_NAME com o código de paciente $PATIENT_ID..."
    curl "https://$CLIENT_NAME.getname.noharm.ai/patient-name/$PATIENT_ID"

    echo "Executando teste simples no serviço Anony..."
    curl -X PUT -H 'Accept: application/json' -H 'Content-Type: application/json' \
        http://localhost/clean -d '{"TEXT" : "FISIOTERAPIA TRAUMATO - MANHÃ Henrique Dias, 38 anos. Exercícios metabólicos de extremidades inferiores. Realizo mobilização patelar e leve mobilização de flexão de joelho conforme liberado pelo Dr Marcelo Arocha. Oriento cuidados e posicionamentos."}'
}

main() {
    if [ "$#" -ne 13 ]; then
        echo "Uso: $0 <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> <GETNAME_SSL_URL> <DB_TYPE> <DB_HOST> <DB_DATABASE> <DB_PORT> <DB_USER> <DB_PASS> <DB_QUERY> <DB_MULTI_QUERY> <CLIENT_NAME> <PATIENT_ID>"
        exit 1
    fi

    AWS_ACCESS_KEY_ID=$1
    AWS_SECRET_ACCESS_KEY=$2
    GETNAME_SSL_URL=$3
    DB_TYPE=$4
    DB_HOST=$5
    DB_DATABASE=$6
    DB_PORT=$7
    DB_USER=$8
    DB_PASS=$9
    DB_QUERY=${10}
    DB_MULTI_QUERY=${11}
    CLIENT_NAME=${12}
    PATIENT_ID=${13}

    test_docker
    install_containers
    test_services

    echo "Script executado com sucesso!"
}

main "$@"