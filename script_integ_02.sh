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

    # Clonar o repositório depois de remover o diretório antigo
    git clone https://github.com/noharm-ai/nifi-composer/
    check_status "Falha ao clonar o repositório 'nifi-composer'"

    cd nifi-composer/
    ./update_secrets.sh
    check_status "Falha ao executar o script 'update_secrets.sh'"

    # Verificando se o arquivo noharm.env foi criado corretamente
    if [ ! -f "$ENV_FILE_PATH" ]; then
        echo "### Erro: Arquivo noharm.env não foi encontrado após a execução de update_secrets.sh."
        exit 1
    fi

    # Armazenando a senha gerada
    PASSWORD=$(grep "SINGLE_USER_CREDENTIALS_PASSWORD" "$ENV_FILE_PATH" | cut -d '=' -f2)

    cd ..  # Voltando ao diretório anterior após clonar e gerar senha
}

# Função para remover a pasta "nifi-composer" e recomeçar o processo
remove_and_clone_repository() {
    if [ -d "nifi-composer" ]; then
        echo "### Pasta 'nifi-composer' já existe. Excluindo para garantir nova instalação..."
        rm -rf nifi-composer  # Removendo completamente o diretório existente
        check_status "Falha ao remover a pasta 'nifi-composer'"
    fi

    clone_repository_and_generate_password  # Clona o repositório e gera a senha
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
        cd nifi-composer  # Certificando-se de que estamos no diretório correto
        docker compose up -d
        if [ $? -eq 0 ]; then
            success=true
            break
        fi
        echo "### Falha ao fazer pull da imagem, aguardando $sleep_time segundos antes de tentar novamente..."
        sleep $sleep_time
        retry_count=$((retry_count+1))
        sleep_time=$((sleep_time + 30))  # Aumentar o tempo de espera a cada tentativa
        cd ..  # Voltando ao diretório original
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
    docker exec --user="root" -it "$container_name" apt install awscli wget -y
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
    
    # Verificando se o arquivo noharm.env existe
    if [ ! -f "$ENV_FILE_PATH" ];then
        echo "### Erro: Arquivo noharm.env não encontrado. Verifique a execução de update_secrets.sh."
        exit 1
    fi
    
    # Atualizando o arquivo noharm.env com as variáveis necessárias
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
        sed -i "s|^DB_QUERY=.*|DB_QUERY=SELECT DISTINCT NOME FROM VW_GETNAME WHERE FKPESSOA = $DB_QUERY|" "$ENV_FILE_PATH"
    else
        sed -i "s|^DB_QUERY=.*|DB_QUERY=SELECT DISTINCT NOME FROM VW_GETNAME WHERE FKPESSOA = {}|" "$ENV_FILE_PATH"
    fi

    if [[ "$DB_MULTI_QUERY" =~ \{\} ]]; then
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=\"$DB_MULTI_QUERY\"|" "$ENV_FILE_PATH"
    elif [ -n "$DB_MULTI_QUERY" ]; then
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=SELECT DISTINCT(NOME), FKPESSOA FROM VW_GETNAME WHERE FKPESSOA IN ($DB_MULTI_QUERY)|" "$ENV_FILE_PATH"
    else
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=SELECT DISTINCT(NOME), FKPESSOA FROM VW_GETNAME WHERE FKPESSOA IN ({})|" "$ENV_FILE_PATH"
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

# Function to modify the renew_cert.sh script inside nifi-getname container
modify_renew_cert_script() {
    echo "### Modificando o arquivo renew_cert.sh para usar a variável de ambiente GETNAME_SSL_URL..."
    # Captura o nome completo do container que contém "getname"
    container_name=$(docker ps --format "{{.Names}}" | grep "getname")
    
    # Verifica se o container foi encontrado
    if [ -z "$container_name" ]; then
        echo "### Erro: Nenhum container com 'getname' no nome foi encontrado."
        exit 1
    fi
    
    # Replace line in the renew_cert.sh script
    docker exec --user="root" -it "$container_name" sed -i "s|SSL_URL=.*|SSL_URL=${GETNAME_SSL_URL}|" /app/renew_cert.sh
    check_status "Falha ao modificar o script renew_cert.sh no container $container_name"

    echo "### Modificação do renew_cert.sh concluída com sucesso."
}

# Função principal que controla a execução do script
main() {
    if [ "$#" -lt 15 ]; then
        echo "### Uso: $0 <REINSTALL_MODE> <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY> <GETNAME_SSL_URL> <DB_TYPE> <DB_HOST> <DB_DATABASE> <DB_PORT> <DB_USER> <DB_PASS> <DB_QUERY> <PATIENT_ID> <DB_MULTI_QUERY> <IDS_PATIENT> <CLIENT_NAME>"
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
    PATIENT_ID=${12}
    DB_MULTI_QUERY=${13}  # Passa a consulta ou os valores
    IDS_PATIENT=${14}
    CLIENT_NAME=${15}

    # Verifica se REINSTALL_MODE está "true"
    if [[ "$REINSTALL_MODE" == "true" ]]; then
        echo "### Modo de reinstalação ativado. Excluindo pasta e reinstalando do zero..."
        remove_and_clone_repository  # Remove e clona novamente a pasta
        cleanup_containers  # Remove containers anteriores se necessário
        install_containers  # Inicia a instalação dos containers
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

    # Aguardar 1 minuto antes de executar o comando de geração de chaves
    echo "### Aguardando 1 minuto para garantir que o container noharm-nifi esteja totalmente iniciado..."
    sleep 60

    # Executa o comando de geração de chaves
    echo "### Executando comando de geração de chaves no container noharm-nifi..."
    docker exec --user="root" -t noharm-nifi sh -c /opt/nifi/scripts/ext/genkeypair.sh
    check_status "Falha ao executar o comando de geração de chaves no container noharm-nifi"

    # Modify renew_cert.sh after the containers are up
    modify_renew_cert_script

    # Reiniciando o container noharm-getname após modificar ssl_url
    echo "### Reiniciando o serviço noharm-getname para aplicar as modificações do ssl..."
    docker restart noharm-getname
    check_status "Falha ao reiniciar o container noharm-getname"

    # Verificação e instalação do AWS CLI no noharm-nifi
    test_aws_cli_in_nifi

    # Testa se os serviços estão funcionando corretamente
    test_services

    echo "### Script executado com sucesso!"
    
    # Exibindo a senha somente no final após o sucesso
    echo "### Senha gerada para o usuário 'nifi_noharm': $PASSWORD"
    echo "### Por favor, coloque essa senha no '1password', com o usuário 'nifi_noharm', dentro da seção 'Nifi server'."

    # Verificando se o arquivo noharm.env existe e exibindo seu conteúdo
    if [ -f "$ENV_FILE_PATH" ]; then
        echo "### Exibindo o conteúdo do arquivo noharm.env:"
        cat "$ENV_FILE_PATH"
    else
        echo "### Erro: Arquivo noharm.env não encontrado para exibição."
    fi

    # Executando o comando para exibir configurações de segurança no nifi.properties
    echo "### Exibindo configurações de segurança do arquivo nifi.properties..."
    docker exec --user="root" -it noharm-nifi /bin/bash -c "cat ./conf/nifi.properties | grep security && exit"

    # Reiniciando o container noharm-nifi após exibir as configurações de segurança
    echo "### Reiniciando o serviço noharm-nifi para aplicar as configurações de segurança..."
    docker restart noharm-nifi
    check_status "Falha ao reiniciar o container noharm-nifi"
}

main "$@"
