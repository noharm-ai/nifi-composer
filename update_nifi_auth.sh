#!/bin/bash
set -euo pipefail

CONTAINER_NAME="noharm-nifi"
NIFI_CONF_DIR="/opt/nifi/nifi-current/conf"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_ROOT="/opt/nifi/nifi-current/conf"
BACKUP_DIR="$BACKUP_ROOT/backup_$TIMESTAMP"

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

echo "==========================================="
echo "   🔧 GESTOR DE CONFIGURAÇÃO DO NiFi"
echo "==========================================="
echo "1 - Ativar login com o Google (OIDC)"
echo "2 - Reverter backup de configurações"
echo "3 - Criar novo usuário"
echo "-------------------------------------------"
read -rp "Escolha uma opção (1, 2 ou 3): " OPCAO
echo "-------------------------------------------"

if [ "$OPCAO" == "1" ]; then
  echo "🔐 Ativar login com o Google (OIDC)"
  read -rp "Informe o Client ID do Google Cloud: " GOOGLE_CLIENT_ID
  read -rp "Informe o Client Secret do Google Cloud: " GOOGLE_CLIENT_SECRET
  if [[ -z "$GOOGLE_CLIENT_ID" || -z "$GOOGLE_CLIENT_SECRET" ]]; then
    echo "❌ Client ID e Secret obrigatórios. Abortando."
    exit 1
  fi

  echo "📦 Criando backup dos arquivos originais..."
  docker exec "$CONTAINER_NAME" bash -c "mkdir -p $BACKUP_DIR && cp $NIFI_CONF_DIR/{authorizations.xml,authorizers.xml,users.xml,login-identity-providers.xml,nifi.properties} $BACKUP_DIR/"

  echo "📝 Substituindo arquivos XML..."
  
  # === authorizations.xml (COMPLETO com TODAS as políticas) ===
  docker exec -i "$CONTAINER_NAME" bash -c "cat > $NIFI_CONF_DIR/authorizations.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<authorizations>
    <policies>
        <policy identifier="f99bccd1-a30e-3e4a-98a2-dbc708edc67f" resource="/flow" action="R">
            <group identifier="noharm-admins-group"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </policy>
        <policy identifier="38456ee0-4aba-3060-aa54-c7183616b5fc" resource="/data/process-groups/73aaa803-019a-1000-3f23-fd92c83c0f98" action="R">
            <user identifier="417cb115-fa4e-3aa8-815b-7298647b7632"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
            <user identifier="717cb115-fa4e-3aa8-815b-7298647b7635"/>
            <user identifier="617cb115-fa4e-3aa8-815b-7298647b7634"/>
            <user identifier="817cb115-fa4e-3aa8-815b-7298647b7636"/>
            <user identifier="917cb115-fa4e-3aa8-815b-7298647b7637"/>
            <user identifier="c17cb115-fa4e-3aa8-815b-7298647b763a"/>
            <user identifier="a17cb115-fa4e-3aa8-815b-7298647b7638"/>
            <user identifier="517cb115-fa4e-3aa8-815b-7298647b7633"/>
            <user identifier="b17cb115-fa4e-3aa8-815b-7298647b7639"/>
        </policy>
        <policy identifier="1782232a-943f-39c6-a372-f55d3bd5d8d7" resource="/data/process-groups/73aaa803-019a-1000-3f23-fd92c83c0f98" action="W">
            <user identifier="417cb115-fa4e-3aa8-815b-7298647b7632"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
            <user identifier="717cb115-fa4e-3aa8-815b-7298647b7635"/>
            <user identifier="617cb115-fa4e-3aa8-815b-7298647b7634"/>
            <user identifier="817cb115-fa4e-3aa8-815b-7298647b7636"/>
            <user identifier="917cb115-fa4e-3aa8-815b-7298647b7637"/>
            <user identifier="c17cb115-fa4e-3aa8-815b-7298647b763a"/>
            <user identifier="a17cb115-fa4e-3aa8-815b-7298647b7638"/>
            <user identifier="517cb115-fa4e-3aa8-815b-7298647b7633"/>
            <user identifier="b17cb115-fa4e-3aa8-815b-7298647b7639"/>
        </policy>
        <policy identifier="6e1d4108-52b7-3cb9-9f58-8ae3e7efe750" resource="/process-groups/73aaa803-019a-1000-3f23-fd92c83c0f98" action="R">
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </policy>
        <policy identifier="9911dd63-09b0-3a2a-a5e3-e41015a12519" resource="/process-groups/73aaa803-019a-1000-3f23-fd92c83c0f98" action="W">
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </policy>
        <policy identifier="b8775bd4-704a-34c6-987b-84f2daf7a515" resource="/restricted-components" action="W">
            <group identifier="noharm-admins-group"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </policy>
        <policy identifier="627410be-1717-35b4-a06f-e9362b89e0b7" resource="/tenants" action="R">
            <group identifier="noharm-admins-group"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </policy>
        <policy identifier="15e4e0bd-cb28-34fd-8587-f8d15162cba5" resource="/tenants" action="W">
            <group identifier="noharm-admins-group"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </policy>
        <policy identifier="ff96062a-fa99-36dc-9942-0f6442ae7212" resource="/policies" action="R">
            <group identifier="noharm-admins-group"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </policy>
        <policy identifier="ad99ea98-3af6-3561-ae27-5bf09e1d969d" resource="/policies" action="W">
            <group identifier="noharm-admins-group"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </policy>
        <policy identifier="2e1015cb-0fed-3005-8e0d-722311f21a03" resource="/controller" action="R">
            <group identifier="noharm-admins-group"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </policy>
        <policy identifier="c6322e6c-4cc1-3bcc-91b3-2ed2111674cf" resource="/controller" action="W">
            <group identifier="noharm-admins-group"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </policy>
        <policy identifier="287edf48-da72-359b-8f61-da5d4c45a270" resource="/proxy" action="W">
            <group identifier="noharm-admins-group"/>
        </policy>
        <policy identifier="7843d899-019a-1000-9c7c-2940852b1238" resource="/provenance" action="R">
            <group identifier="noharm-admins-group"/>
        </policy>
        <policy identifier="7844eaf5-019a-1000-60f1-ff76d7594812" resource="/site-to-site" action="R">
            <group identifier="noharm-admins-group"/>
        </policy>
        <policy identifier="784514dd-019a-1000-28b5-ab1bb87d1e27" resource="/system" action="R">
            <group identifier="noharm-admins-group"/>
        </policy>
        <policy identifier="7845757e-019a-1000-f10f-47b5336a8bdd" resource="/counters" action="R">
            <group identifier="noharm-admins-group"/>
        </policy>
        <policy identifier="78459fc6-019a-1000-199b-94898cdfa7d1" resource="/counters" action="W">
            <group identifier="noharm-admins-group"/>
        </policy>
    </policies>
</authorizations>
EOF

  # === authorizers.xml (COMPLETO com todos os usuários) ===
  docker exec -i "$CONTAINER_NAME" bash -c "cat > $NIFI_CONF_DIR/authorizers.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<authorizers>
    <userGroupProvider>
        <identifier>file-user-group-provider</identifier>
        <class>org.apache.nifi.authorization.FileUserGroupProvider</class>
        <property name="Users File">./conf/users.xml</property>
        <property name="Legacy Authorized Users File"></property>
        <property name="Initial User Identity 1">diogenes@noharm.ai</property>
        <property name="Initial User Identity 2">henrique@noharm.ai</property>
        <property name="Initial User Identity 3">julia@noharm.ai</property>
        <property name="Initial User Identity 4">juliana@noharm.ai</property>
        <property name="Initial User Identity 5">olimar@noharm.ai</property>
        <property name="Initial User Identity 6">david@noharm.ai</property>
        <property name="Initial User Identity 7">arthur@noharm.ai</property>
        <property name="Initial User Identity 8">joaquim@noharm.ai</property>
        <property name="Initial User Identity 9">marcelo@noharm.ai</property>
        <property name="Initial User Identity 10">nifi@noharm.ai</property>
        <property name="Synchronize Interval">10 mins</property>
    </userGroupProvider>
    <accessPolicyProvider>
        <identifier>file-access-policy-provider</identifier>
        <class>org.apache.nifi.authorization.FileAccessPolicyProvider</class>
        <property name="Authorizations File">./conf/authorizations.xml</property>
        <property name="Users File">./conf/users.xml</property>
        <property name="User Group Provider">file-user-group-provider</property>
        <property name="Initial Admin Identity">nifi@noharm.ai</property>
        <property name="Node Identity 1">henrique@noharm.ai</property>
        <property name="Node Identity 2">julia@noharm.ai</property>
        <property name="Node Identity 3">juliana@noharm.ai</property>
        <property name="Node Identity 4">olimar@noharm.ai</property>
        <property name="Node Identity 5">david@noharm.ai</property>
        <property name="Node Identity 6">arthur@noharm.ai</property>
        <property name="Node Identity 7">joaquim@noharm.ai</property>
        <property name="Node Identity 8">marcelo@noharm.ai</property>
        <property name="Node Identity 9">diogenes@noharm.ai</property>
        <property name="Legacy Authorized Users File"></property>
    </accessPolicyProvider>
    <authorizer>
        <identifier>managed-authorizer</identifier>
        <class>org.apache.nifi.authorization.StandardManagedAuthorizer</class>
        <property name="Access Policy Provider">file-access-policy-provider</property>
        <property name="User Group Provider">file-user-group-provider</property>
    </authorizer>
</authorizers>
EOF

  # === login-identity-providers.xml ===
  docker exec -i "$CONTAINER_NAME" bash -c "cat > $NIFI_CONF_DIR/login-identity-providers.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<loginIdentityProviders>
</loginIdentityProviders>
EOF

  # === users.xml (COMPLETO com todos os 10 usuários) ===
  docker exec -i "$CONTAINER_NAME" bash -c "cat > $NIFI_CONF_DIR/users.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<tenants>
    <groups>
        <group identifier="noharm-admins-group" name="NoHarm Admins">
            <user identifier="417cb115-fa4e-3aa8-815b-7298647b7632"/>
            <user identifier="517cb115-fa4e-3aa8-815b-7298647b7633"/>
            <user identifier="617cb115-fa4e-3aa8-815b-7298647b7634"/>
            <user identifier="717cb115-fa4e-3aa8-815b-7298647b7635"/>
            <user identifier="817cb115-fa4e-3aa8-815b-7298647b7636"/>
            <user identifier="917cb115-fa4e-3aa8-815b-7298647b7637"/>
            <user identifier="a17cb115-fa4e-3aa8-815b-7298647b7638"/>
            <user identifier="b17cb115-fa4e-3aa8-815b-7298647b7639"/>
            <user identifier="c17cb115-fa4e-3aa8-815b-7298647b763a"/>
            <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b"/>
        </group>
    </groups>
    <users>
        <user identifier="417cb115-fa4e-3aa8-815b-7298647b7632" identity="diogenes@noharm.ai"/>
        <user identifier="517cb115-fa4e-3aa8-815b-7298647b7633" identity="henrique@noharm.ai"/>
        <user identifier="617cb115-fa4e-3aa8-815b-7298647b7634" identity="julia@noharm.ai"/>
        <user identifier="717cb115-fa4e-3aa8-815b-7298647b7635" identity="juliana@noharm.ai"/>
        <user identifier="817cb115-fa4e-3aa8-815b-7298647b7636" identity="olimar@noharm.ai"/>
        <user identifier="917cb115-fa4e-3aa8-815b-7298647b7637" identity="david@noharm.ai"/>
        <user identifier="a17cb115-fa4e-3aa8-815b-7298647b7638" identity="arthur@noharm.ai"/>
        <user identifier="b17cb115-fa4e-3aa8-815b-7298647b7639" identity="joaquim@noharm.ai"/>
        <user identifier="c17cb115-fa4e-3aa8-815b-7298647b763a" identity="marcelo@noharm.ai"/>
        <user identifier="d17cb115-fa4e-3aa8-815b-7298647b763b" identity="nifi@noharm.ai"/>
    </users>
</tenants>
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

  echo "✅ Configuração OIDC concluída com sucesso!"
  echo "📋 Backup salvo em: $BACKUP_DIR"

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
  
  USER_ID=$(generate_uuid)
  echo "🆔 Criando usuário: $NEW_EMAIL"
  echo "🔑 UUID gerado: $USER_ID"
  
  # Adiciona usuário ao users.xml
  docker exec "$CONTAINER_NAME" bash -c "sed -i '/<\/users>/ i\        <user identifier=\"$USER_ID\" identity=\"$NEW_EMAIL\"\/>' '$NIFI_CONF_DIR/users.xml'"
  
  # Adiciona usuário ao grupo de admins
  docker exec "$CONTAINER_NAME" bash -c "sed -i '/<group identifier=\"noharm-admins-group\".*>/a\            <user identifier=\"$USER_ID\"\/>' '$NIFI_CONF_DIR/users.xml'"
  
  # Adiciona ao authorizers.xml como Initial User Identity
  NEXT_NUM=$(docker exec "$CONTAINER_NAME" bash -c "grep -c 'Initial User Identity' '$NIFI_CONF_DIR/authorizers.xml' || echo 0")
  NEXT_NUM=$((NEXT_NUM + 1))
  docker exec "$CONTAINER_NAME" bash -c "sed -i '/<property name=\"Synchronize Interval\">/i\        <property name=\"Initial User Identity $NEXT_NUM\">$NEW_EMAIL<\/property>' '$NIFI_CONF_DIR/authorizers.xml'"
  
  echo "✅ Usuário $NEW_EMAIL criado com sucesso!"
  echo "   - Adicionado ao users.xml"
  echo "   - Adicionado ao grupo noharm-admins-group"
  echo "   - Adicionado ao authorizers.xml"

else
  echo "❌ Opção inválida."
  exit 1
fi

echo ""
echo "==========================================="
read -rp "🔄 Deseja reiniciar o container $CONTAINER_NAME agora? (s/n): " R
if [[ "$R" =~ ^[sS]$ ]]; then
  echo "🔄 Reiniciando container..."
  docker restart "$CONTAINER_NAME"
  echo "✅ Container reiniciado com sucesso!"
  echo "⏳ Aguarde alguns segundos para o NiFi inicializar..."
else
  echo "⏸️ Reinício cancelado. Execute manualmente: docker restart $CONTAINER_NAME"
fi

echo "==========================================="
echo "✨ Processo finalizado!"
echo "==========================================="