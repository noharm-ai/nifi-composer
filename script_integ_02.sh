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

validate_disk_requirements() {
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}' | tr -d 'G')  # Captura o espaço total em GB
    DISK_AVAILABLE=$(df -h / | awk 'NR==2 {print $4}' | tr -d 'G')  # Captura o espaço livre em GB
    
    echo "Espaço total em disco: ${DISK_TOTAL}GB"
    echo "Espaço disponível em disco: ${DISK_AVAILABLE}GB"

    if [[ "$DISK_TOTAL" -lt 95 ]]; then
        echo "Espaço total em disco insuficiente. Necessário pelo menos 95GB."
        read -p "Deseja continuar mesmo assim? (y/n): " choice
        if [[ "$choice" != "y" ]]; then
            exit 1
        fi
        echo "Envie um e-mail para o cliente informando que os requisitos mínimos não foram atendidos."
    fi

    if [[ "$DISK_AVAILABLE" -lt 75 ]]; then
        echo "Espaço disponível em disco insuficiente. Necessário pelo menos 75GB."
        read -p "Deseja continuar mesmo assim? (y/n): " choice
        if [[ "$choice" != "y" ]]; then
            exit 1
        fi
        echo "Envie um e-mail para o cliente informando que os requisitos mínimos não foram atendidos."
    fi
}

validate_memory_requirements() {
    MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')  # Captura a memória total em MB
    MEM_AVAILABLE=$(get_memory_available)  # Captura a memória disponível em MB
    
    echo "Memória total: ${MEM_TOTAL}MB"
    echo "Memória disponível: ${MEM_AVAILABLE}MB"

    if [[ "$MEM_TOTAL" -lt 3500 ]]; then
        echo "Memória total insuficiente. Necessário pelo menos 3.5GB."
        read -p "Deseja continuar mesmo assim? (y/n): " choice
        if [[ "$choice" != "y" ]]; then
            exit 1
        fi
        echo "Envie um e-mail para o cliente informando que os requisitos mínimos não foram atendidos."
    fi
}

validate_cpu_requirements() {
    VCPUS=$(nproc)  # Captura o número de vCPUs disponíveis
    echo "vCPUs disponíveis: ${VCPUS}"

    if [[ "$VCPUS" -lt 4 ]]; then
        echo "vCPUs insuficientes. Necessário pelo menos 4 vCPUs."
        read -p "Deseja continuar mesmo assim? (y/n): " choice
        if [[ "$choice" != "y" ]]; then
            exit 1
        fi
        echo "Envie um e-mail para o cliente informando que os requisitos mínimos não foram atendidos."
    fi
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
    
    # Mudança de proprietário do socket do Docker
    sudo chown $USER /var/run/docker.sock

    # Verifica se o grupo "docker" já existe
    if getent group docker > /dev/null 2>&1; then
        echo "Grupo 'docker' já existe, continuando..."
    else
        sudo groupadd docker
        echo "Grupo 'docker' criado com sucesso."
    fi
    
    # Adiciona o usuário atual ao grupo "docker"
    sudo usermod -aG docker $USER

    echo "Configuração do Docker como usuário não-root concluída."
    echo "Por favor, faça logout e login novamente ou reinicie seu terminal para aplicar as alterações."
}

main() {
    echo "Data Atual: $(date)"
    echo "Validando requisitos de sistema..."

    # Exibe os valores gerais de espaço em disco e memória
    df -h
    df -h /var/lib/docker || echo "Docker não está instalado, pulando /var/lib/docker."
    free -m

    # Validação de disco
    validate_disk_requirements

    # Validação de memória
    validate_memory_requirements

    # Validação de CPU
    validate_cpu_requirements

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