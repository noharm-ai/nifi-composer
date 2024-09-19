#!/bin/bash

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

    if [ -d "nifi-composer" ]; then
        echo "### Pasta 'nifi-composer' já existe. Excluindo para garantir nova instalação..."
        rm -rf nifi-composer
    fi

    git clone https://github.com/noharm-ai/nifi-composer/
    check_status "Falha ao clonar o repositório 'nifi-composer'"

    cd nifi-composer/
    ./update_secrets.sh
    check_status "Falha ao executar o script 'update_secrets.sh'"

    PASSWORD=$(grep "SINGLE_USER_CREDENTIALS_PASSWORD" noharm.env | cut -d '=' -f2)
    echo "### Senha gerada para o usuário 'nifi_noharm': $PASSWORD"
    echo "### Por favor, coloque essa senha no '1password', com o usuário 'nifi_noharm', dentro da seção 'Nifi server'."

    cd ..  # Voltando ao diretório anterior após clonar e gerar senha
}

# Função para parar e remover containers, redes, volumes, e imagens
cleanup_containers() {
    echo "### Parando e removendo containers e volumes..."
    
    # Certifique-se de que o arquivo docker-compose.yml foi clonado antes de tentar remover containers
    if [ -f "nifi-composer/docker-compose.yml" ]; then
        cd nifi-composer  # Entrando no diretório correto onde está o docker-compose.yml
        docker compose down --volumes --remove-orphans
        check_status "Falha ao parar e remover containers"
        echo "### Containers removidos com sucesso."
        cd ..  # Voltando ao diretório original
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
    sleep_time=30  # 30 segundos entre tentativas

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

# Função para instalar o AWS CLI no container noharm-nifi
install_aws_cli_in_nifi() {
    container_name="noharm-nifi"
    echo "### Instalando AWS CLI no container $container_name..."
    docker exec --user="root" -it "$container_name" apt update
    docker exec --user="root" -it "$container_name" apt install awscli -y
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
    echo "### Verificando se o AWS CLI está funcionando dentro do container..."
    docker exec --user="root" -it noharm-nifi /bin/bash -c "aws s3 ls && exit"
    check_status "Falha ao verificar o AWS CLI no container noharm-nifi"

    echo "### Verificando se o serviço está funcionando para o cliente $CLIENT_NAME com o código de paciente $PATIENT_ID..."
    curl "https://$CLIENT_NAME.getname.noharm.ai/patient-name/$PATIENT_ID"
    check_status "Falha ao verificar o serviço para o cliente $CLIENT_NAME com o código de paciente $PATIENT_ID"

    echo "### Executando teste simples no serviço Anony..."
    curl -X PUT -H 'Accept: application/json' -H 'Content-Type: application/json' \
        http://localhost/clean -d '{"TEXT" : "FISIOTERAPIA TRAUMATO - MANHÃ Henrique Dias, 38 anos. Exercícios metabólicos de extremidades inferiores. Realizo mobilização patelar e leve mobilização de flexão de joelho conforme liberado pelo Dr Marcelo Arocha. Oriento cuidados e posicionamentos."}'
    check_status "Falha ao testar o serviço Anony"
}

# Função para atualizar o arquivo de ambiente
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

# Função para instalar e iniciar os containers com Docker Compose
install_containers() {
    echo "### Instalando containers com Docker Compose..."

    update_env_file

    echo "### Iniciando containers com retry..."
    retry_docker_pull
}

# Função principal que controla a execução do script
main() {
    if [ "$#" -lt 14 ]; then
        echo "### Uso: $0 <REINSTALL_MODE> <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> <GETNAME_SSL_URL> <DB_TYPE> <DB_HOST> <DB_DATABASE> <DB_PORT> <DB_USER> <DB_PASS> <DB_QUERY> <DB_MULTI_QUERY> <CLIENT_NAME> <PATIENT_ID>"
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
    DB_QUERY=${11}  # Passa a consulta ou o valor
    DB_MULTI_QUERY=${12}  # Passa a consulta ou os valores
    CLIENT_NAME=${13}
    PATIENT_ID=${14}

    # Verifica se REINSTALL_MODE está "true"
    if [[ "$REINSTALL_MODE" == "true" ]]; then
        echo "### Modo de reinstalação ativado. Clonando repositório e reiniciando do zero..."
        clone_repository_and_generate_password
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

    # Verificação e instalação do AWS CLI no noharm-nifi
    test_aws_cli_in_nifi

    # Testa se os serviços estão funcionando corretamente
    test_services

    echo "### Script executado com sucesso!"
}

main "$@"
