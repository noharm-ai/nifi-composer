#!/bin/bash

set -e  # Habilita a interrupção do script em caso de erro
trap 'echo "Erro detectado. Revertendo mudanças..."; rollback' ERR

rollback() {
    if [ "$DOCKER_INSTALLED" = true ]; then
        sudo apt-get remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    if [ "$GIT_INSTALLED" = true ]; then
        sudo apt-get remove --purge -y git
        sudo yum remove -y git
    fi

    if [ "$NANO_INSTALLED" = true ]; then
        sudo apt-get remove --purge -y nano
        sudo yum remove -y nano
    fi

    echo "Reversão concluída."
}

get_memory_available() {
    # Tenta capturar a memória disponível usando diferentes abordagens

    # Primeira tentativa: usando o campo 'available' (sistemas modernos)
    MEM_AVAILABLE=$(free -m | awk '/^Mem:/{print $7}')
    if [[ -n "$MEM_AVAILABLE" ]]; then
        echo "$MEM_AVAILABLE"
        return
    fi

    # Segunda tentativa: somando memória livre + buffers/cache (sistemas mais antigos)
    MEM_AVAILABLE=$(free -m | awk '/Mem:/ {print $4+$6}')
    if [[ -n "$MEM_AVAILABLE" ]]; then
        echo "$MEM_AVAILABLE"
        return
    fi

    # Terceira tentativa: usando o campo 'free' diretamente (pode não ser preciso, mas uma estimativa)
    MEM_AVAILABLE=$(free -m | awk '/^Mem:/{print $4}')
    if [[ -n "$MEM_AVAILABLE" ]]; then
        echo "$MEM_AVAILABLE"
        return
    fi

    # Se todas as tentativas falharem, retorna "N/A" e segue com a execução
    echo "N/A"
}

validate_requirements() {
    echo "Data Atual: $(date)"
    echo "Validando requisitos de sistema..."

    # Exibe os valores gerais de espaço em disco e memória
    df -h
    df -h /var/lib/docker || echo "Docker não está instalado, pulando /var/lib/docker."
    free -m

    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}' | tr -d 'G')  # Captura o espaço total em GB
    DISK_AVAILABLE=$(df -h / | awk 'NR==2 {print $4}' | tr -d 'G')  # Captura o espaço livre em GB
    MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')  # Captura a memória total em MB
    MEM_AVAILABLE=$(get_memory_available)  # Captura a memória disponível em MB
    VCPUS=$(nproc)  # Captura o número de vCPUs disponíveis

    echo "Espaço total em disco: ${DISK_TOTAL}GB"
    echo "Espaço disponível em disco: ${DISK_AVAILABLE}GB"
    echo "Memória total: ${MEM_TOTAL}MB"
    echo "Memória disponível: ${MEM_AVAILABLE}MB"
    echo "vCPUs disponíveis: ${VCPUS}"

    if [[ "$DISK_TOTAL" -lt 100 ]]; then
        echo "Espaço total em disco. Necessário pelo menos 100GB."
        exit 1
    fi

    if [[ "$DISK_AVAILABLE" -lt 75 ]]; then
        echo "Espaço disponível em disco insuficiente. Necessário pelo menos 75GB."
        exit 1
    fi

    if [[ "$MEM_TOTAL" -lt 4096 ]]; then
        echo "Memória total. Necessário pelo menos 4GB."
        exit 1
    fi

    if [[ "$MEM_AVAILABLE" != "N/A" && "$MEM_AVAILABLE" -lt 3072 ]]; then
        echo "Memória disponível insuficiente. Necessário pelo menos 3GB."
        exit 1
    elif [[ "$MEM_AVAILABLE" == "N/A" ]]; then
        echo "Memória disponível não pôde ser determinada, mas continuando..."
    fi

    if [[ "$VCPUS" -lt 4 ]]; then
        echo "vCPUs insuficientes. Necessário pelo menos 4 vCPUs."
        exit 1
    fi

    echo "Requisitos de sistema validados com sucesso."
}

install_docker_ubuntu_debian() {
    echo "Instalando Docker para Ubuntu/Debian..."
    sudo apt-get update
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git nano

    DOCKER_INSTALLED=true
    GIT_INSTALLED=true
    NANO_INSTALLED=true
}

install_docker_rpm_based() {
    echo "Instalando Docker para distros RPM-based..."
    sudo yum update -y
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git nano

    DOCKER_INSTALLED=true
    GIT_INSTALLED=true
    NANO_INSTALLED=true
}

configure_docker_non_root() {
    echo "Configurando Docker para ser executado como usuário não-root..."
    sudo chown $USER /var/run/docker.sock
    sudo groupadd docker || true
    sudo usermod -aG docker $USER
    newgrp docker
}

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

    validate_requirements

    if [[ -f /etc/debian_version ]]; then
        install_docker_ubuntu_debian
    elif [[ -f /etc/redhat-release ]]; then
        install_docker_rpm_based
    else
        echo "Distribuição Linux não suportada."
        exit 1
    fi

    configure_docker_non_root
    test_docker
    install_containers
    test_services

    echo "Script executado com sucesso!"
}

main "$@"
