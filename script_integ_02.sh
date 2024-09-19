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

    # Verifica se uma query customizada foi passada ou se é necessário usar a query padrão
    if [[ "$DB_QUERY" =~ \{\} ]]; then
        # Se a query contém '{}', usa como query customizada
        sed -i "s|^DB_QUERY=.*|DB_QUERY=$DB_QUERY|" noharm.env
    elif [ -n "$DB_QUERY" ]; then
        # Caso contrário, usa a query padrão e insere o valor
        sed -i "s|^DB_QUERY=.*|DB_QUERY=SELECT DISTINCT NOME FROM VW_PACIENTES WHERE FKPESSOA = $DB_QUERY|" noharm.env
    else
        # Mantém a query padrão com o placeholder
        sed -i "s|^DB_QUERY=.*|DB_QUERY=SELECT DISTINCT NOME FROM VW_PACIENTES WHERE FKPESSOA = {}|" noharm.env
    fi

    if [[ "$DB_MULTI_QUERY" =~ \{\} ]]; then
        # Se a query contém '{}', usa como query customizada
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=$DB_MULTI_QUERY|" noharm.env
    elif [ -n "$DB_MULTI_QUERY" ]; then
        # Caso contrário, usa a query padrão e insere os valores
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=SELECT DISTINCT(NOME), FKPESSOA FROM VW_PACIENTES WHERE FKPESSOA IN ($DB_MULTI_QUERY)|" noharm.env
    else
        # Mantém a query padrão com o placeholder
        sed -i "s|^DB_MULTI_QUERY=.*|DB_MULTI_QUERY=SELECT DISTINCT(NOME), FKPESSOA FROM VW_PACIENTES WHERE FKPESSOA IN ({})|" noharm.env
    fi

    echo "Arquivo noharm.env atualizado com sucesso."
}

generate_password() {
    echo "Gerando senha para o usuário nifi_noharm..."
    cd nifi-composer/

    # Executa o script para gerar e substituir a senha
    ./update_secrets.sh

    # Captura a senha gerada no arquivo noharm.env
    PASSWORD=$(grep "SINGLE_USER_CREDENTIALS_PASSWORD" noharm.env | cut -d '=' -f2)

    # Exibe a senha gerada no console com a mensagem solicitada
    echo "Senha gerada e aplicada no arquivo noharm.env."
    echo "A senha gerada para o usuário 'nifi_noharm' é: $PASSWORD"
    echo "Por favor, coloque essa senha no '1password', com o usuário 'nifi_noharm', dentro da seção 'Nifi server'."
}

install_containers() {
    echo "Instalando containers com Docker Compose..."
    git clone https://github.com/noharm-ai/nifi-composer/
    cd nifi-composer/
    
    # Gera a senha antes de iniciar os containers
    generate_password

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

restart_services() {
    echo "Reiniciando todos os serviços após a execução dos testes..."
    
    # Reiniciando os containers
    docker restart noharm-nifi
    docker restart noharm-anony
    docker restart noharm-getname
    
    echo "Todos os serviços foram reiniciados com sucesso!"
}

main() {
    if [ "$#" -lt 12 ]; then
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
    DB_QUERY=${10}  # Passa a consulta ou o valor
    DB_MULTI_QUERY=${11}  # Passa a consulta ou os valores
    CLIENT_NAME=${12}
    PATIENT_ID=${13}

    test_docker
    install_containers
    test_services

    restart_services

    echo "Script executado com sucesso!"
}

main "$@"
