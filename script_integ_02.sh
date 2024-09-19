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

retry_docker_pull() {
    retry_count=0
    max_retries=6
    success=false

    while [ $retry_count -lt $max_retries ]; do
        echo "### Tentativa de pull de containers ($((retry_count+1))/$max_retries)..."
        docker compose up -d
        if [ $? -eq 0 ]; then
            success=true
            break
        fi
        echo "### Falha ao fazer pull da imagem, aguardando antes de tentar novamente..."
        sleep 30
        retry_count=$((retry_count+1))
    done

    if [ "$success" = false ]; then
        echo "### Erro: Não foi possível fazer pull da imagem após $max_retries tentativas. Verifique sua conexão e tente novamente."
        exit 1
    fi
}

clear_docker_cache() {
    echo "### Limpando cache do Docker..."
    docker system prune -a -f
    check_status "Falha ao limpar cache do Docker"
    echo "### Cache do Docker limpo com sucesso."
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

    echo "### Iniciando containers..."
    retry_docker_pull
}

test_services() {
    echo "### Verificando se o AWS CLI está funcionando dentro do container..."
    docker exec --user="root" -it noharm-nifi /bin/bash -c "aws s3 ls && exit"
    check_status "Falha ao verificar o AWS CLI no container"

    echo "### Verificando se o serviço está funcionando para o cliente $CLIENT_NAME com o código de paciente $PATIENT_ID..."
    curl "https://$CLIENT_NAME.getname.noharm.ai/patient-name/$PATIENT_ID"
    check_status "Falha ao verificar o serviço para o cliente $CLIENT_NAME"

    echo "### Executando teste simples no serviço Anony..."
    curl -X PUT -H 'Accept: application/json' -H 'Content-Type: application/json' \
        http://localhost/clean -d '{"TEXT" : "FISIOTERAPIA TRAUMATO - MANHÃ Henrique Dias, 38 anos. Exercícios metabólicos de extremidades inferiores. Realizo mobilização patelar e leve mobilização de flexão de joelho conforme liberado pelo Dr Marcelo Arocha. Oriento cuidados e posicionamentos."}'
    check_status "Falha ao executar o teste simples no serviço Anony"
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
        echo "### Uso: $0 <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> <GETNAME_SSL_URL> <DB_TYPE> <DB_HOST> <
