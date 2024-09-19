#!/bin/bash

# Função para verificar o status da execução
check_status() {
    if [ $? -ne 0 ]; then
        echo "### Erro: $1. O script precisa ser reexecutado."
        exit 1
    fi
}

setup_docker_proxy() {
    echo "### Verificando se é necessário configurar proxy para Docker..."
    if [ -n "$HTTP_PROXY" ] || [ -n "$HTTPS_PROXY" ]; then
        echo "### Configurando proxy para Docker..."
        sudo mkdir -p /etc/systemd/system/docker.service.d
        echo "[Service]" | sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null
        echo "Environment=\"HTTP_PROXY=$HTTP_PROXY\"" | sudo tee -a /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null
        echo "Environment=\"HTTPS_PROXY=$HTTPS_PROXY\"" | sudo tee -a /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null
        sudo systemctl daemon-reload
        sudo systemctl restart docker
        check_status "Falha ao configurar o proxy para Docker"
        echo "### Proxy configurado com sucesso."
    else
        echo "### Nenhum proxy configurado."
    fi
}

test_docker() {
    echo "### Testando instalação do Docker..."
    if ! docker ps > /dev/null 2>&1; then
        echo "### Docker não está rodando, iniciando serviço..."
        sudo systemctl start docker
        check_status "Falha ao iniciar o serviço Docker"
    fi
    docker ps
    echo "### Docker está funcionando corretamente."
}

check_connectivity() {
    echo "### Verificando conectividade com o Docker Hub..."
    curl -s https://hub.docker.com > /dev/null
    if [ $? -ne 0 ]; then
        echo "### Erro: Não foi possível conectar ao Docker Hub. Verifique sua conexão de rede."
        exit 1
    fi
    echo "### Conectividade com Docker Hub OK."
}

retry_docker_pull() {
    retry_count=0
    max_retries=6
    success=false
    sleep_time=60  # 60 segundos entre tentativas

    while [ $retry_count -lt $max_retries ]; do
        echo "### Tentativa de pull de containers ($((retry_count+1))/$max_retries)..."
        docker compose up -d
        if [ $? -eq 0 ]; then
            success=true
            break
        fi
        echo "### Falha ao fazer pull da imagem, aguardando $sleep_time segundos antes de tentar novamente..."
        sleep $sleep_time
        retry_count=$((retry_count+1))
        sleep_time=$((sleep_time + 30))  # Aumentar o tempo de espera a cada tentativa
    done

    if [ "$success" = false ]; then
        echo "### Erro: Não foi possível fazer pull da imagem após $max_retries tentativas. Verifique sua conexão e tente novamente."
        exit 1
    fi
}

install_aws_cli_in_container() {
    container_name=$1
    echo "### Instalando AWS CLI no container $container_name..."
    docker exec --user="root" -it "$container_name" apt update
    docker exec --user="root" -it "$container_name" apt install awscli -y
    check_status "Falha ao instalar AWS CLI no container $container_name"
}

test_aws_cli_in_container() {
    container_name=$1
    echo "### Verificando se o AWS CLI está funcionando dentro do container $container_name..."
    docker exec --user="root" -it "$container_name" /bin/bash -c "aws --version"
    if [ $? -ne 0 ]; then
        echo "### AWS CLI não está instalado no container $container_name. Tentando instalar..."
        install_aws_cli_in_container "$container_name"
    else
        echo "### AWS CLI está instalado corretamente no container $container_name."
    fi
}

update_env_file() {
    echo "### Atualizando variáveis de ambiente no arquivo noharm.env..."

    [ -n "$AWS_ACCESS_KEY_ID" ] && sed -i "s|^AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID|" noharm.env
    [ -n "$AWS_SECRET_ACCESS_KEY" ] && sed -i "s|^AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY|" noharm.env
    [ -n "$GETNAME_SSL_URL" ] && sed -i "s|^GETNAME_SSL_URL=.*|GETNAME_SSL_URL=$GETNAME_SSL_URL|" noharm.env
    [ -n "$DB_TYPE" ] && sed -i "s|^DB_TYPE=.*|DB_TYPE=$DB_TYPE|" noharm.env
    [ -n "$DB_HOST" ] && sed -i "s|^DB_HOST=.*|DB_HOST=$DB_HOST|" noharm.env
    [ -n "$DB_DATABASE" ] && sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_DATABASE|" noharm.env
    [ -n "$DB_PORT" ] && sed -i "s|^DB_PORT=.*|DB_PORT=$DB_PORT|" noharm.env
    [ -n "$DB_USER" ] && sed -i "s|^DB_USER=.*|DB_USER=$DB_USER|" noharm.env
    [ -n "$DB_PASS" ] && sed -i "s|^DB_PASS=.*|DB_PASS=$DB_PASS|" noharm.env

    if [[ "$DB_QUERY" =~ \{\} ]]; then
        sed -i "s|^DB_QUERY=.*|DB_QUERY=\"$DB_QUERY\"|" noharm.env
    elif [ -n "$DB_QUERY" ]; then
        sed -i "s|^DB_QUERY=.*|DB_QUERY=SELECT DISTINCT NOME FROM VW_PACIENTES WHERE FKPESSOA = $DB_QUERY|" noharm.env
    else
        sed -i "s|^DB_QUERY=.*|DB_QUERY=SELECT DISTINCT NOME FROM VW_PACIENTES WHERE FKPESSOA = {}|" noharm.env
    fi

    if [[ "$DB_MULTI_QUERY" =~ \{\} ]]; then
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=\"$DB_MULTI_QUERY\"|" noharm.env
    elif [ -n "$DB_MULTI_QUERY" ]; then
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=SELECT DISTINCT(NOME), FKPESSOA FROM VW_PACIENTES WHERE FKPESSOA IN ($DB_MULTI_QUERY)|" noharm.env
    else
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=SELECT DISTINCT(NOME), FKPESSOA FROM VW_PACIENTES WHERE FKPESSOA IN ({})|" noharm.env
    fi

    echo "### Arquivo noharm.env atualizado com sucesso."
}

generate_password() {
    echo "### Gerando senha para o usuário nifi_noharm..."

    if [ -d "nifi-composer" ]; then
        echo "### Pasta 'nifi-composer' já existe. Excluindo..."
        rm -rf nifi-composer
        check_status "Falha ao remover a pasta existente 'nifi-composer'"
    fi

    git clone https://github.com/noharm-ai/nifi-composer/
    check_status "Falha ao clonar o repositório 'nifi-composer'"

    cd nifi-composer/
    ./update_secrets.sh
    check_status "Falha ao executar o script 'update_secrets.sh'"

    PASSWORD=$(grep "SINGLE_USER_CREDENTIALS_PASSWORD" noharm.env | cut -d '=' -f2)
    echo "### Senha gerada para o usuário 'nifi_noharm': $PASSWORD"
    echo "### Por favor, coloque essa senha no '1password', com o usuário 'nifi_noharm', dentro da seção 'Nifi server'."
}

install_containers() {
    echo "### Instalando containers com Docker Compose..."

    if [ -d "nifi-composer" ]; then
        echo "### Pasta 'nifi-composer' já existe. Excluindo..."
        rm -rf nifi-composer
        check_status "Falha ao remover a pasta existente 'nifi-composer'"
    fi

    git clone https://github.com/noharm-ai/nifi-composer/
    check_status "Falha ao clonar o repositório 'nifi-composer'"

    cd nifi-composer/

    generate_password
    update_env_file

    check_connectivity

    echo "### Iniciando containers..."
    retry_docker_pull
}

test_services() {
    echo "### Verificando se o AWS CLI está funcionando dentro do container noharm-nifi..."
    test_aws_cli_in_container "noharm-nifi"
}

restart_services() {
    echo "### Reiniciando todos os serviços após a execução dos testes..."
    
    docker restart noharm-nifi || echo "### Aviso: Falha ao reiniciar o container noharm-nifi"
    docker restart noharm-anony || echo "### Aviso: Falha ao reiniciar o container noharm-anony"
    docker restart noharm-getname || echo "### Aviso: Falha ao reiniciar o container noharm-getname"

    echo "### Todos os serviços foram reiniciados (ou foram encontradas falhas)."
}

main() {
    if [ "$#" -lt 13 ]; then
        echo "### Uso: $0 <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> <GETNAME_SSL_URL> <DB_TYPE> <DB_HOST> <DB_DATABASE> <DB_PORT> <DB_USER> <DB_PASS> <DB_QUERY> <DB_MULTI_QUERY> <CLIENT_NAME> <PATIENT_ID>"
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
    DB_QUERY=${10}  # Passa a consulta ou o valor
    DB_MULTI_QUERY=${11}  # Passa a consulta ou os valores
    CLIENT_NAME=${12}
    PATIENT_ID=${13}

    if [ -n "$ID_PATIENT" ] && [[ "$DB_QUERY" =~ \{\} ]]; then
        DB_QUERY=$(echo "$DB_QUERY" | sed "s|{}|$ID_PATIENT|")
    fi

    if [ -n "$IDS_PATIENT" ] && [[ "$DB_MULTI_QUERY" =~ \{\} ]]; then
        DB_MULTI_QUERY=$(echo "$DB_MULTI_QUERY" | sed "s|{}|$IDS_PATIENT|")
    fi

    test_docker
    install_containers
    test_services

    restart_services

    echo "### Script executado com sucesso!"
}

main "$@"