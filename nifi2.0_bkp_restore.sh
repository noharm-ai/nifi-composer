#!/usr/bin/env bash
set -euo pipefail

# Uso:
#   ./nifi_backup_restore.sh CLIENTE [min|full]
# Ex:
#   ./nifi_backup_restore.sh HCPA min
#   ./nifi_backup_restore.sh HCPA full

CLIENT="${1:-}"
SCOPE="${2:-min}"    # min | full

if [[ -z "${CLIENT}" ]]; then
  echo "Uso: $0 CLIENTE [min|full]"
  exit 1
fi

# --- Configuráveis (com defaults sensatos) ---
BUCKET="${BUCKET:-s3://noharm-nifi}"
# Diretórios no host (bind-mounts do compose)
NIFI_BASE="${NIFI_BASE:-./nifi}"
REG_BASE="${REG_BASE:-./nifi-registry}"
# Prefixos no S3
PREFIX_NIFI="${PREFIX_NIFI:-${CLIENT}/backup/nifi}"
PREFIX_REG="${PREFIX_REG:-${CLIENT}/backup/registry}"

# Containers (ajuste se tiver nomes diferentes)
NIFI_CTN="${NIFI_CTN:-noharm-nifi}"
REG_CTN="${REG_CTN:-nifi-registry}"

command -v aws >/dev/null 2>&1 || { echo "aws cli não encontrado no host."; exit 2; }

echo ">> Restaurando backup (${SCOPE}) do cliente '${CLIENT}' a partir de ${BUCKET}"

# Parar NiFi (e Registry no full, para evitar inconsistência)
if docker ps --format '{{.Names}}' | grep -q "^${NIFI_CTN}$"; then
  echo "-> Parando container ${NIFI_CTN}"
  docker stop "${NIFI_CTN}" >/dev/null
fi
if [[ "${SCOPE}" == "full" ]] && docker ps --format '{{.Names}}' | grep -q "^${REG_CTN}$"; then
  echo "-> Parando container ${REG_CTN}"
  docker stop "${REG_CTN}" >/dev/null || true
fi

# Restaurar conf
mkdir -p "${NIFI_BASE}/conf"
echo "-> Restaurando NiFi conf/"
aws s3 sync "${BUCKET}/${PREFIX_NIFI}/conf" "${NIFI_BASE}/conf" \
  --exclude "*" \
  --include "flow.json.gz" \
  --include "nifi.properties" \
  --include "authorizers.xml" \
  --include "users.xml" \
  --include "groups.xml" \
  --include "login-identity-providers.xml" \
  --include "bootstrap.conf"

# Extras (drivers/certs/scripts)
for d in drivers certs scripts; do
  echo "-> Restaurando ${d}/ (se existir no S3)"
  mkdir -p "${NIFI_BASE}/${d}"
  aws s3 sync "${BUCKET}/${PREFIX_NIFI}/${d}" "${NIFI_BASE}/${d}" || true
done

if [[ "${SCOPE}" == "full" ]]; then
  # Restaurar repositórios/estado/logs
  for d in state flowfile_repository content_repository provenance_repository database_repository logs; do
    echo "-> Restaurando ${d}/ (se existir no S3)"
    mkdir -p "${NIFI_BASE}/${d}"
    aws s3 sync "${BUCKET}/${PREFIX_NIFI}/${d}" "${NIFI_BASE}/${d}" || true
  done

  # Registry
  if aws s3 ls "${BUCKET}/${PREFIX_REG}/" >/dev/null 2>&1; then
    echo "-> Restaurando Registry (conf, flow_storage, database, logs)"
    for d in conf flow_storage database logs; do
      mkdir -p "${REG_BASE}/${d}"
      aws s3 sync "${BUCKET}/${PREFIX_REG}/${d}" "${REG_BASE}/${d}" || true
    done
  fi
fi

# Garantir permissões (UID/GID do usuário 'nifi' costuma ser 1000)
echo "-> Ajustando permissões nos diretórios montados"
sudo chown -R 1000:1000 "${NIFI_BASE}" || true
if [[ -d "${REG_BASE}" ]]; then
  sudo chown -R 1000:1000 "${REG_BASE}" || true
fi

# Substituição da chave sensível:
# Como estamos restaurando o 'nifi.properties' do backup, a 'nifi.sensitive.props.key' já vem correta.
# (Se você preferir preservar o arquivo local e apenas trocar a key, posso manter a tua lógica anterior.)
echo "-> 'nifi.properties' restaurado do backup (inclui nifi.sensitive.props.key)"

# Subir Registry (se houver) e NiFi
if [[ "${SCOPE}" == "full" ]]; then
  if docker ps -a --format '{{.Names}}' | grep -q "^${REG_CTN}$"; then
    echo "-> Iniciando ${REG_CTN}"
    docker start "${REG_CTN}" >/dev/null || true
  fi
fi

echo "-> Iniciando ${NIFI_CTN}"
docker start "${NIFI_CTN}" >/dev/null

echo ">> Restauração concluída."