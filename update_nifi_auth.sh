#!/bin/bash
set -euo pipefail

CONTAINER_NAME="noharm-nifi"
NIFI_CONF_DIR="/opt/nifi/nifi-current/conf"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_ROOT="/opt/nifi/nifi-current/conf"
BACKUP_DIR="$BACKUP_ROOT/backup_$TIMESTAMP"

# Funções auxiliares
log()  { echo -e "\n==== $* ====\n" >&2; }
erro() { echo -e "\n[ERRO] $*\n" >&2; exit 1; }

checa_comando() {
  command -v "$1" >/dev/null 2>&1 || erro "Comando '$1' não encontrado.";
}

espera_container_subir() {
  local name="$1"
  local tentativas=60
  local i=0
  log "Aguardando container '${name}' ficar disponível..."
  until docker ps --format '{{.Names}}' | grep -qx "$name"; do
    i=$((i+1))
    if (( i > tentativas )); then
      erro "Container '${name}' não ficou disponível a tempo."
    fi
    sleep 2
  done
  log "Container '${name}' está disponível!"
}

# Gerar UUID para novo usuário
generate_uuid() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import uuid; print(str(uuid.uuid4()))
PY
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
  fi
}

# Fazer backup do flow antes de recriar
backup_flow() {
  local container="$1"
  local backup_local="./nifi-flow-backup"
  
  log "Fazendo backup do flow do NiFi..."
  mkdir -p "$backup_local"
  
  # Backup dos arquivos críticos do flow
  docker cp "${container}:/opt/nifi/nifi-current/conf/flow.xml.gz" "$backup_local/" 2>/dev/null || \
  docker cp "${container}:/opt/nifi/nifi-current/conf/flow.json.gz" "$backup_local/" 2>/dev/null || \
    log "Aviso: Nenhum arquivo de flow encontrado (flow.xml.gz ou flow.json.gz)"
  
  # Backup dos repositórios
  # docker cp "${container}:/opt/nifi/nifi-current/state" "$backup_local/" 2>/dev/null || true
  # docker cp "${container}:/opt/nifi/nifi-current/database_repository" "$backup_local/" 2>/dev/null || true
  # docker cp "${container}:/opt/nifi/nifi-current/flowfile_repository" "$backup_local/" 2>/dev/null || true
  # docker cp "${container}:/opt/nifi/nifi-current/content_repository" "$backup_local/" 2>/dev/null || true
  
  log "Backup do flow salvo em: $backup_local"
  echo "$backup_local"
}

# Verificar se docker-compose está disponível
checa_comando docker

echo "==========================================="
echo "   🔧 GESTOR DE CONFIGURAÇÃO DO NiFi"
echo "==========================================="
echo "1 - Ativar login com o Google (OIDC)"
echo "2 - Reverter backup de configurações"
echo "3 - Criar novo usuário"
echo "==========================================="
echo "                  DEBUG                    "
echo "==========================================="
echo "Opções disponíveis:"
echo " 4 - Buscar UUID do root process group"
echo "==========================================="
echo "-------------------------------------------"
read -rp "Escolha uma opção (1, 2, 3 ou 4): " OPCAO
echo "-------------------------------------------"

if [ "$OPCAO" == "1" ]; then
  echo "🔐 Ativar login com o Google (OIDC)"
  echo ""
  
  echo ""
  read -rp "Informe o Client ID do Google Cloud: " GOOGLE_CLIENT_ID
  read -srp "Informe o Client Secret do Google Cloud: " GOOGLE_CLIENT_SECRET
  if [[ -z "$GOOGLE_CLIENT_ID" || -z "$GOOGLE_CLIENT_SECRET" ]]; then
    echo "❌ Client ID e Secret obrigatórios. Abortando."
    exit 1
  fi

  echo ""
  echo "👥 Configuração de Usuários"
  echo "-------------------------------------------"
  
  # Lista de todos os usuários que devem existir
  ALL_USERS=(
    "diogenes@noharm.ai"
    "henrique@noharm.ai"
    "julia@noharm.ai"
    "juliana@noharm.ai"
    "olimar@noharm.ai"
    "david@noharm.ai"
    "arthur@noharm.ai"
    "joaquim@noharm.ai"
    "marcelo@noharm.ai"
    "nifi@noharm.ai"
    "CN=localhost"
  )
  
  # Mapeia índice do usuário para UUID (mantém consistência)
  USER_UUIDS=(
    "417cb115-fa4e-3aa8-815b-7298647b7632"  # diogenes@noharm.ai
    "517cb115-fa4e-3aa8-815b-7298647b7633"  # henrique@noharm.ai
    "617cb115-fa4e-3aa8-815b-7298647b7634"  # julia@noharm.ai
    "717cb115-fa4e-3aa8-815b-7298647b7635"  # juliana@noharm.ai
    "817cb115-fa4e-3aa8-815b-7298647b7636"  # olimar@noharm.ai
    "917cb115-fa4e-3aa8-815b-7298647b7637"  # david@noharm.ai
    "a17cb115-fa4e-3aa8-815b-7298647b7638"  # arthur@noharm.ai
    "b17cb115-fa4e-3aa8-815b-7298647b7639"  # joaquim@noharm.ai
    "c17cb115-fa4e-3aa8-815b-7298647b763a"  # marcelo@noharm.ai
    "e17cb115-fa4e-3aa8-815b-7298647b763c"  # nifi@noharm.ai
    "c7db2353-019a-1000-29b4-2c6ca9877f13"  # CN=localhost
  )
  
  echo "📋 Usuários disponíveis:"
  for i in "${!ALL_USERS[@]}"; do
    echo "  $((i+1)) - ${ALL_USERS[$i]}"
  done
  echo ""
  
  read -rp "Escolha o número do ADMIN PRINCIPAL (1-${#ALL_USERS[@]}): " ADMIN_CHOICE
  
  # Validar escolha
  if ! [[ "$ADMIN_CHOICE" =~ ^[0-9]+$ ]] || [ "$ADMIN_CHOICE" -lt 1 ] || [ "$ADMIN_CHOICE" -gt "${#ALL_USERS[@]}" ]; then
    echo "❌ Escolha inválida. Abortando."
    exit 1
  fi
  
  ADMIN_EMAIL="${ALL_USERS[$((ADMIN_CHOICE-1))]}"
  echo ""
  echo "✅ Admin selecionado: $ADMIN_EMAIL"
  echo ""

  # Fazer backup do flow ANTES de qualquer mudança
  FLOW_BACKUP=$(backup_flow "$CONTAINER_NAME")

  echo "📦 Criando backup dos arquivos originais..."
  docker exec "$CONTAINER_NAME" bash -c "mkdir -p $BACKUP_DIR && cp $NIFI_CONF_DIR/{authorizations.xml,authorizers.xml,users.xml,login-identity-providers.xml,nifi.properties} $BACKUP_DIR/ 2>/dev/null || true"

  echo "🗑️ Removendo users.xml e authorizations.xml para inicialização limpa..."
  docker exec "$CONTAINER_NAME" bash -c "rm -f $NIFI_CONF_DIR/users.xml $NIFI_CONF_DIR/authorizations.xml"

  echo "📝 Configurando authorizers.xml com grupo..."
  
  # Remove duplicatas mantendo a ordem
  UNIQUE_USERS=()
  for user in "${ALL_USERS[@]}"; do
    if [ ${#UNIQUE_USERS[@]} -eq 0 ] || [[ ! " ${UNIQUE_USERS[@]} " =~ " ${user} " ]]; then
      UNIQUE_USERS+=("$user")
    fi
  done
  
  # Cria o XML do authorizers COM GRUPO
  AUTHORIZERS_XML="<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>
<authorizers>
    <userGroupProvider>
        <identifier>file-user-group-provider</identifier>
        <class>org.apache.nifi.authorization.FileUserGroupProvider</class>
        <property name=\"Users File\">./conf/users.xml</property>
        <property name=\"Legacy Authorized Users File\"></property>"
  
  # Adiciona Initial User Identity para cada usuário
  USER_NUM=1
  for user in "${UNIQUE_USERS[@]}"; do
    AUTHORIZERS_XML="${AUTHORIZERS_XML}
        <property name=\"Initial User Identity ${USER_NUM}\">${user}</property>"
    USER_NUM=$((USER_NUM + 1))
  done
  
  # ADICIONA O GRUPO INICIAL
  AUTHORIZERS_XML="${AUTHORIZERS_XML}
        <property name=\"Initial User Group 1\">NoHarm Admins</property>"
  
  AUTHORIZERS_XML="${AUTHORIZERS_XML}
    </userGroupProvider>
    <accessPolicyProvider>
        <identifier>file-access-policy-provider</identifier>
        <class>org.apache.nifi.authorization.FileAccessPolicyProvider</class>
        <property name=\"User Group Provider\">file-user-group-provider</property>
        <property name=\"Authorizations File\">./conf/authorizations.xml</property>
        <property name=\"Legacy Authorized Users File\"></property>
        <property name=\"Initial Admin Identity\">${ADMIN_EMAIL}</property>"

  AUTHORIZERS_XML="${AUTHORIZERS_XML}
    </accessPolicyProvider>
    <authorizer>
        <identifier>managed-authorizer</identifier>
        <class>org.apache.nifi.authorization.StandardManagedAuthorizer</class>
        <property name=\"Access Policy Provider\">file-access-policy-provider</property>
    </authorizer>
</authorizers>"
  
  # Escreve o arquivo authorizers.xml
  echo "$AUTHORIZERS_XML" | docker exec -i "$CONTAINER_NAME" bash -c "cat > $NIFI_CONF_DIR/authorizers.xml"
  
  # Verifica se o arquivo foi criado
  if ! docker exec "$CONTAINER_NAME" bash -c "test -s $NIFI_CONF_DIR/authorizers.xml"; then
    echo "❌ ERRO: Não foi possível criar o arquivo authorizers.xml"
    exit 1
  fi
  
  echo "✓ Arquivo authorizers.xml criado com sucesso"

  # Cria o users.xml COM O GRUPO
  echo "📝 Criando users.xml com grupo..."
  
  USERS_XML="<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>
<tenants>
    <groups>
        <group identifier=\"noharm-admins-group\" name=\"NoHarm Admins\">"
  
  # Adiciona todos os usuários ao grupo
  for i in "${!UNIQUE_USERS[@]}"; do
    user="${UNIQUE_USERS[$i]}"
    uuid="${USER_UUIDS[$i]}"
    USERS_XML="${USERS_XML}
            <user identifier=\"${uuid}\"/>"
  done
  
  USERS_XML="${USERS_XML}
        </group>
    </groups>
    <users>"
  
  # Adiciona os usuários
  for i in "${!UNIQUE_USERS[@]}"; do
    user="${UNIQUE_USERS[$i]}"
    uuid="${USER_UUIDS[$i]}"
    USERS_XML="${USERS_XML}
        <user identifier=\"${uuid}\" identity=\"${user}\"/>"
  done
  
  USERS_XML="${USERS_XML}
    </users>
</tenants>"
  
  # Escreve o arquivo users.xml
  echo "$USERS_XML" | docker exec -i "$CONTAINER_NAME" bash -c "cat > $NIFI_CONF_DIR/users.xml"
  
  if ! docker exec "$CONTAINER_NAME" bash -c "test -s $NIFI_CONF_DIR/users.xml"; then
    echo "❌ ERRO: Não foi possível criar o arquivo users.xml"
    exit 1
  fi
  
  echo "✓ Arquivo users.xml criado com sucesso"

  echo "📝 Criando authorizations.xml com políticas para o grupo..."

  # Descobrir o UUID do root process group - MÉTODO SIMPLIFICADO
  echo "🔍 Obtendo UUID do root process group..."
  ROOT_PG_ID=""

  # Procurar em flow.json.gz
  if docker exec "$CONTAINER_NAME" bash -c "test -f /opt/nifi/nifi-current/conf/flow.json.gz"; then
      echo "✅ Encontrado flow.json.gz, extraindo UUID..."
      ROOT_PG_ID=$(
        docker exec "$CONTAINER_NAME" bash -c '
          zcat /opt/nifi/nifi-current/conf/flow.json.gz |
          jq -r ".rootGroup.instanceIdentifier" 2>/dev/null || 
          zcat /opt/nifi/nifi-current/conf/flow.json.gz |
          grep -A 10 "\"rootGroup\"" |
          grep "\"instanceIdentifier\"" |
          head -1 |
          grep -o "\"instanceIdentifier\":\"[^\"]*\"" |
          cut -d"\"" -f4
        '
      )
      IP_ID="????"
  fi

  # Se ainda não encontrou, usar fallback
  if [[ -z "$ROOT_PG_ID" ]]; then
      echo "⚠️  Não foi possível obter o UUID do process group automaticamente"
      echo "💡 Dica: O NiFi criará um novo UUID quando iniciar sem flow existente"
      read -rp "📝 Digite o UUID do root process group (ou Enter para usar padrão): " ROOT_PG_ID
      
      if [[ -z "$ROOT_PG_ID" ]]; then
          # Gerar um UUID específico para o process group
          ROOT_PG_ID=$(generate_uuid)
          echo "🔧 Usando UUID gerado: $ROOT_PG_ID"
      fi
  else
      echo "✅ UUID do root process group encontrado: $ROOT_PG_ID"
  fi

  # Função para gerar políticas de process group
  generate_pg_policies() {
    local PG_UUID="$1"
    local GROUP_ID="$2"
    local IP_ID="$3"

    local P1=$(generate_uuid)
    local P2=$(generate_uuid)
    local P3=$(generate_uuid)
    local P4=$(generate_uuid)
    local IP1=$(generate_uuid)
    local IP2=$(generate_uuid)
    local IP3=$(generate_uuid)

    cat <<EOF
        <policy identifier="$P1" resource="/process-groups/$PG_UUID" action="R">
            <group identifier="$GROUP_ID"/>
        </policy>
        <policy identifier="$P2" resource="/process-groups/$PG_UUID" action="W">
            <group identifier="$GROUP_ID"/>
        </policy>
        <policy identifier="$P3" resource="/data/process-groups/$PG_UUID" action="W">
            <group identifier="$GROUP_ID"/>
        </policy>
        <policy identifier="$P4" resource="/data/process-groups/$PG_UUID" action="R">
            <group identifier="$GROUP_ID"/>
        </policy>
        <policy identifier="$IP1" resource="/policies/input-ports/$IP_ID" action="R">
            <group identifier="noharm-admins-group"/>
        </policy>
        <policy identifier="$IP2" resource="/policies/input-ports/$IP_ID" action="W">
            <group identifier="noharm-admins-group"/>
        </policy>
        <policy identifier="$IP3" resource="/data-transfer/input-ports/$IP_ID" action="W">
            <group identifier="noharm-admins-group"/>
        </policy>
        
EOF
}

  # Cria o authorizations.xml com políticas dinâmicas
  AUTHORIZATIONS_XML='<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <authorizations>
      <policies>'

  # Adiciona políticas globais
  AUTHORIZATIONS_XML="${AUTHORIZATIONS_XML}
          <policy identifier=\"$(generate_uuid)\" resource=\"/flow\" action=\"R\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/restricted-components\" action=\"W\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/tenants\" action=\"R\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/tenants\" action=\"W\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/policies\" action=\"R\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/policies\" action=\"W\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/controller\" action=\"R\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/controller\" action=\"W\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/proxy\" action=\"W\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/provenance\" action=\"R\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/site-to-site\" action=\"R\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/system\" action=\"R\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/counters\" action=\"R\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>
          <policy identifier=\"$(generate_uuid)\" resource=\"/counters\" action=\"W\">
              <group identifier=\"noharm-admins-group\"/>
          </policy>"

  # Adiciona políticas específicas do process group
  AUTHORIZATIONS_XML="${AUTHORIZATIONS_XML}
  $(generate_pg_policies "$ROOT_PG_ID" "noharm-admins-group" "$IP_ID")"

  AUTHORIZATIONS_XML="${AUTHORIZATIONS_XML}
      </policies>
  </authorizations>"

  # Escreve o arquivo authorizations.xml
  echo "$AUTHORIZATIONS_XML" | docker exec -i "$CONTAINER_NAME" bash -c "cat > $NIFI_CONF_DIR/authorizations.xml"

  if ! docker exec "$CONTAINER_NAME" bash -c "test -s $NIFI_CONF_DIR/authorizations.xml"; then
      echo "❌ ERRO: Não foi possível criar o arquivo authorizations.xml"
      exit 1
  fi

  echo "✓ Arquivo authorizations.xml criado com políticas dinâmicas para o process group: $ROOT_PG_ID"

  # === login-identity-providers.xml ===
  docker exec -i "$CONTAINER_NAME" bash -c "cat > $NIFI_CONF_DIR/login-identity-providers.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<loginIdentityProviders>
</loginIdentityProviders>
EOF

  echo "⚙️ Atualizando nifi.properties..."
  docker exec "$CONTAINER_NAME" bash -c "sed -i \
      -e 's|^nifi.security.user.authorizer=.*|nifi.security.user.authorizer=managed-authorizer|' \
      -e 's|^nifi.security.user.login.identity.provider=.*|nifi.security.user.login.identity.provider=|' \
      -e 's|^nifi.security.allow.anonymous.authentication=.*|nifi.security.allow.anonymous.authentication=false|' \
      -e 's|^nifi.security.user.jws.key.rotation.period=.*|nifi.security.user.jws.key.rotation.period=PT1H|' \
      -e 's|^nifi.security.ocsp.responder.url=.*|nifi.security.ocsp.responder.url=|' \
      -e 's|^nifi.security.ocsp.responder.certificate=.*|nifi.security.ocsp.responder.certificate=|' \
      -e 's|^nifi.security.user.oidc.discovery.url=.*|nifi.security.user.oidc.discovery.url=https://accounts.google.com/.well-known/openid-configuration|' \
      -e \"s|^nifi.security.user.oidc.client.id=.*|nifi.security.user.oidc.client.id=$GOOGLE_CLIENT_ID|\" \
      -e \"s|^nifi.security.user.oidc.client.secret=.*|nifi.security.user.oidc.client.secret=$GOOGLE_CLIENT_SECRET|\" \
      -e 's|^nifi.security.user.oidc.claim.identifying.user=.*|nifi.security.user.oidc.claim.identifying.user=email|' \
      -e 's|^nifi.security.user.oidc.additional.scopes=.*|nifi.security.user.oidc.additional.scopes=email,profile,openid|' \
      -e 's|^nifi.security.user.oidc.connect.timeout=.*|nifi.security.user.oidc.connect.timeout=10 secs|' \
      -e 's|^nifi.security.user.oidc.read.timeout=.*|nifi.security.user.oidc.read.timeout=10 secs|' \
      -e 's|^nifi.security.identity.mapping.pattern.email=.*|nifi.security.identity.mapping.pattern.email=^(.*@noharm\\\\.ai)$|' \
      -e 's|^nifi.security.identity.mapping.value.email=.*|nifi.security.identity.mapping.value.email=\$1|' \
      -e 's|^nifi.security.identity.mapping.transform.email=.*|nifi.security.identity.mapping.transform.email=LOWER|' \
      $NIFI_CONF_DIR/nifi.properties"

  echo ""
  echo "✅ Configuração OIDC concluída com sucesso!"
  echo "📋 Admin configurado: $ADMIN_EMAIL"
  echo "📋 Grupo 'NoHarm Admins' criado com ${#UNIQUE_USERS[@]} usuários"
  echo "📋 Backup salvo em: $BACKUP_DIR"
  echo "📋 Backup do flow salvo em: $FLOW_BACKUP"
  echo ""

elif [ "$OPCAO" == "2" ]; then
  echo "📂 Listando backups disponíveis..."
  docker exec "$CONTAINER_NAME" bash -c "ls -1t $BACKUP_ROOT | grep '^backup_' || echo 'Nenhum backup encontrado'"
  echo ""
  read -rp "Nome da pasta de backup para restaurar (ex: backup_20241112150530): " RESTORE
  
  if docker exec "$CONTAINER_NAME" bash -c "test -d $BACKUP_ROOT/$RESTORE"; then
    echo "♻️ Restaurando backup $RESTORE..."
    docker exec "$CONTAINER_NAME" bash -c "cp $BACKUP_ROOT/$RESTORE/* $NIFI_CONF_DIR/"
    echo "✅ Backup restaurado com sucesso!"
  else
    echo "❌ Backup não encontrado: $RESTORE"
    exit 1
  fi

elif [ "$OPCAO" == "3" ]; then
  read -rp "Digite o e-mail do novo usuário (ex: usuario@noharm.ai): " NEW_EMAIL
  
  if [[ ! "$NEW_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "❌ E-mail inválido."
    exit 1
  fi
  
  # Verifica se os arquivos necessários existem
  if ! docker exec "$CONTAINER_NAME" bash -c "test -f $NIFI_CONF_DIR/authorizers.xml"; then
    echo "❌ Arquivo authorizers.xml não encontrado. Execute a opção 1 primeiro."
    exit 1
  fi
  
  # Converte para lowercase
  NEW_EMAIL=$(echo "$NEW_EMAIL" | tr '[:upper:]' '[:lower:]')
  USER_ID=$(generate_uuid)
  
  echo ""
  echo "🆔 UUID gerado: $USER_ID"
  
  # Backup dos arquivos atuais
  docker exec "$CONTAINER_NAME" bash -c "mkdir -p $BACKUP_DIR && cp $NIFI_CONF_DIR/{authorizations.xml,authorizers.xml,users.xml} $BACKUP_DIR/ 2>/dev/null || true"
  
  # 1. Adiciona ao authorizers.xml como Initial User Identity
  NEXT_NUM=$(docker exec "$CONTAINER_NAME" bash -c "grep -c 'Initial User Identity' '$NIFI_CONF_DIR/authorizers.xml' || echo 0")
  NEXT_NUM=$((NEXT_NUM + 1))
  
  # Adiciona a propriedade no local correto
  docker exec "$CONTAINER_NAME" bash -c "sed -i '/<property name=\"Initial User Group 1\">NoHarm Admins<\/property>/a\\        <property name=\"Initial User Identity $NEXT_NUM\">$NEW_EMAIL<\/property>' '$NIFI_CONF_DIR/authorizers.xml'"
  
  # 2. Adiciona ao users.xml como usuário
  if docker exec "$CONTAINER_NAME" bash -c "grep -q \"<user identifier=\\\"$USER_ID\\\"\" '$NIFI_CONF_DIR/users.xml'"; then
    echo "⚠️  Usuário já existe no users.xml"
  else
    docker exec "$CONTAINER_NAME" bash -c "sed -i '/<\\/users>/ i\\\\        <user identifier=\"$USER_ID\" identity=\"$NEW_EMAIL\"\\/>' '$NIFI_CONF_DIR/users.xml'"
  fi
  
  # 3. Adiciona ao grupo NoHarm Admins
  if docker exec "$CONTAINER_NAME" bash -c "grep -q \"<user identifier=\\\"$USER_ID\\\"\" '$NIFI_CONF_DIR/users.xml'"; then
    docker exec "$CONTAINER_NAME" bash -c "sed -i '/<group identifier=\"noharm-admins-group\".*>/a\\\\            <user identifier=\"$USER_ID\"\\/>' '$NIFI_CONF_DIR/users.xml'"
  fi
  
  # 5. Também remove state dos repositórios para forçar reinicialização limpa
  docker exec "$CONTAINER_NAME" bash -c "rm -rf /opt/nifi/nifi-current/state/* 2>/dev/null || true"
  
  echo "✅ Usuário $NEW_EMAIL adicionado!"
  echo "📋 Alterações realizadas:"
  echo "   ✓ Adicionado como Initial User Identity $NEXT_NUM no authorizers.xml"
  echo "   ✓ Adicionado ao users.xml com UUID: $USER_ID"
  echo "   ✓ Adicionado ao grupo 'NoHarm Admins'"
  echo ""
  echo "⚠️  Para ativar, o container será reiniciado agora."

elif [ "$OPCAO" == "4" ]; then
  echo "🔍 Obtendo UUID do root process group..."
  ROOT_PG_ID=""

  # Procurar em flow.json.gz
  if docker exec "$CONTAINER_NAME" bash -c "test -f /opt/nifi/nifi-current/conf/flow.json.gz"; then
      echo "✅ Encontrado flow.json.gz, extraindo UUID..."
      ROOT_PG_ID=$(
        docker exec "$CONTAINER_NAME" bash -c '
          zcat /opt/nifi/nifi-current/conf/flow.json.gz |
          jq -r ".rootGroup.instanceIdentifier" 2>/dev/null || 
          zcat /opt/nifi/nifi-current/conf/flow.json.gz |
          grep -A 10 "\"rootGroup\"" |
          grep "\"instanceIdentifier\"" |
          head -1 |
          grep -o "\"instanceIdentifier\":\"[^\"]*\"" |
          cut -d"\"" -f4
        '
      )
      echo "✅ UUID do root process group encontrado: $ROOT_PG_ID"
  else
      echo "⚠️ flow.json.gz não encontrado."
  fi
else
  echo "❌ Opção inválida."
  exit 1
fi

echo ""

# Verifica se uma operação que requer reinício foi executada
if [[ "$OPCAO" == "1" || "$OPCAO" == "3" ]]; then
  echo "==========================================="
  read -rp "🔄 Deseja REINICIAR o container $CONTAINER_NAME agora? (s/n): " R
  if [[ "$R" =~ ^[sS]$ ]]; then
    log "🚀 REINICIANDO container..."
    docker restart "$CONTAINER_NAME"
    
    espera_container_subir "$CONTAINER_NAME"
    
    echo "✅ Container reiniciado com sucesso!"
    echo "⏳ Aguardando NiFi processar configurações..."
    sleep 10
    
    # Verificar se os arquivos foram criados
    echo "🔍 Verificando criação dos arquivos de autorização..."
    sleep 20
    
    if docker exec "$CONTAINER_NAME" bash -c "test -f $NIFI_CONF_DIR/users.xml"; then
      echo "✓ users.xml está presente"
    else
      echo "⚠️  users.xml ainda não foi criado"
    fi
    
    if docker exec "$CONTAINER_NAME" bash -c "test -f $NIFI_CONF_DIR/authorizations.xml"; then
      echo "✓ authorizations.xml foi criado"
    else
      echo "⚠️  authorizations.xml ainda não foi criado"
    fi
    
    echo ""
    echo "💡 IMPORTANTE: Aguarde 1-2 minutos antes de fazer login no NiFi"
    echo "   O NiFi precisa processar as configurações de autorização"
    
  else
    echo "⏸️ Reinício adiado. Você DEVE reiniciar o container manualmente para aplicar as mudanças."
    echo "Execute: docker restart $CONTAINER_NAME"
  fi
  
elif [[ "$OPCAO" == "2" ]]; then
  read -rp "🔄 Deseja reiniciar o container $CONTAINER_NAME agora? (s/n): " R
  if [[ "$R" =~ ^[sS]$ ]]; then
    log "🚀 REINICIANDO container..."
    docker restart "$CONTAINER_NAME"
    
    espera_container_subir "$CONTAINER_NAME"
    echo "✅ Container reiniciado com sucesso!"
  else
    echo "⏸️ Reinício adiado. Execute manualmente: docker restart $CONTAINER_NAME"
  fi
fi

echo "==========================================="
echo "✨ Processo finalizado!"
echo "==========================================="
