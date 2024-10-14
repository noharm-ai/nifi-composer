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

    MEM_AVAILABLE=$(free -m | awk '/^Mem:/{print $7}')
    if [[ -n "$MEM_AVAILABLE" ]]; then
        echo "$MEM_AVAILABLE"
        return
    fi

    MEM_AVAILABLE=$(free -m | awk '/Mem:/ {print $4+$6}')
    if [[ -n "$MEM_AVAILABLE" ]]; then
        echo "$MEM_AVAILABLE"
        return
    fi

    MEM_AVAILABLE=$(free -m | awk '/^Mem:/{print $4}')
    if [[ -n "$MEM_AVAILABLE" ]]; then
        echo "$MEM_AVAILABLE"
        return
    fi

    MEM_AVAILABLE=$(free -m | awk '/^Mem:/{print $3}')
    if [[ -n "$MEM_AVAILABLE" ]]; then
        echo "$MEM_AVAILABLE"
        return
    fi

    echo "N/A"
}

ask_continue() {
    local resource_name=$1
    local min_value=$2
    local actual_value=$3

    echo "$resource_name insuficiente. Necessário pelo menos $min_value. Disponível: $actual_value."
    echo "Por favor, tire um print desta tela e envie um e-mail ao cliente informando que os requisitos mínimos não foram atendidos."

    read -p "Deseja continuar a instalação mesmo com $resource_name insuficiente? (y/n): " choice
    case "$choice" in
        y|Y ) echo "Continuando com a instalação...";;
        n|N ) echo "Instalação interrompida devido a $resource_name insuficiente."; exit 1;;
        * ) echo "Opção inválida. Instalação interrompida."; exit 1;;
    esac
}

validate_requirements() {
    echo "Data Atual: $(date)"
    echo "Validando requisitos de sistema..."

    df -h
    df -h /var/lib/docker || echo "Docker não está instalado, pulando /var/lib/docker."
    free -m

    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}' | tr -d 'G')  # Captura o espaço total em GB
    DISK_AVAILABLE=$(df -h / | awk 'NR==2 {print $4}' | tr -d 'G')  # Captura o espaço livre em GB
    MEM_TOTAL_1=$(free -m | awk '/^Mem.:/{print $2}')  # Captura a memória total em MB
    MEM_TOTAL_2=$(free -m | awk '/^Mem:/{print $2}')  # Captura a memória total em MB
    MEM_AVAILABLE=$(get_memory_available)  # Captura a memória disponível em MB
    VCPUS=$(nproc)  # Captura o número de vCPUs disponíveis

    if [ -z "$MEM_TOTAL_1" ]; then
        MEM_TOTAL=$MEM_TOTAL_2
    else
        MEM_TOTAL=$MEM_TOTAL_1
    fi

    echo "Espaço total em disco: ${DISK_TOTAL}GB"
    echo "Espaço disponível em disco: ${DISK_AVAILABLE}GB"
    echo "Memória total: ${MEM_TOTAL}MB"
    echo "Memória disponível: ${MEM_AVAILABLE}MB"
    echo "vCPUs disponíveis: ${VCPUS}"

    if [[ "$DISK_TOTAL" -lt 95 ]]; then
        ask_continue "Espaço total em disco" "95GB" "${DISK_TOTAL}GB"
    fi

    if [[ "$DISK_AVAILABLE" -lt 75 ]]; then
        ask_continue "Espaço disponível em disco" "75GB" "${DISK_AVAILABLE}GB"
    fi

    if [[ "$MEM_TOTAL" -lt 3500 ]]; then
        ask_continue "Memória total" "3.5GB" "${MEM_TOTAL}MB"
    fi

    if [[ "$VCPUS" -lt 4 ]]; then
        ask_continue "vCPUs" "4" "$VCPUS"
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

    if getent group docker > /dev/null 2>&1; then
        echo "Grupo 'docker' já existe, continuando..."
    else
        sudo groupadd docker
        echo "Grupo 'docker' criado com sucesso."
    fi
    
    sudo usermod -aG docker $USER

    echo "Configuração do Docker como usuário não-root concluída."
    echo "Por favor, faça logout e login novamente ou reinicie seu terminal para aplicar as alterações."
}

main() {
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

    echo "Configuração inicial concluída. Por favor, faça logout e login novamente ou reinicie o terminal e, em seguida, execute o script 'script_integ_02.sh'."
}

main "$@"
