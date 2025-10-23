#!/usr/bin/env bash
set -euo pipefail

# Uso:
#   ./nifi_create_backup.sh CLIENTE [min|full]
# Ex:
#   ./nifi_create_backup.sh HCPA min
#   ./nifi_create_backup.sh HCPA full

CLIENT="${1:-}"
SCOPE="${2:-min}"   # min | full

if [[ -z "${CLIENT}" ]]; then
  echo "Uso: $0 CLIENTE [min|full]"
  exit 1
fi

# --- Configuráveis (com defaults sensatos) ---
BUCKET="${BUCKET:-s3://noharm-nifi}"
# Diretórios no host (bind-mounts do compose)
NIFI_BASE="${NIFI_BASE:-./nifi}"
REG_BASE="${REG_BASE:-./nifi-registry}"
# Prefixo no S3
PREFIX_NIFI="${PREFIX_NIFI:-${CLIENT}/backup/nifi}"
PREFIX_REG="${PREFIX_REG:-${CLIENT}/backup/registry}"

# --- Pré-checagens ---
command -v aws >/dev/null 2>&1 || { echo "aws cli não encontrado no host."; exit 2; }
[[ -d "${NIFI_BASE}" ]] || { echo "Diretório ${NIFI_BASE} não existe (bind-mount do NiFi)."; exit 3; }
# Registry é opcional, só alerta no modo full
if [[ "${SCOPE}" == "full" && ! -d "${REG_BASE}" ]]; then
  echo "Aviso: ${REG_BASE} não existe; ignorando backup do Registry."
fi

echo ">> Iniciando backup (${SCOPE}) do cliente '${CLIENT}' para ${BUCKET}"

# --- Essencial (conf) ---
# conf: flow.json.gz, nifi.properties, authorizers.xml, users.xml, groups.xml, login-identity-providers.xml, bootstrap.conf
if [[ -d "${NIFI_BASE}/conf" ]]; then
  echo "-> Backup conf/"
  aws s3 sync "${NIFI_BASE}/conf" "${BUCKET}/${PREFIX_NIFI}/conf" \
    --exclude "*" \
    --include "flow.json.gz" \
    --include "nifi.properties" \
    --include "authorizers.xml" \
    --include "users.xml" \
    --include "groups.xml" \
    --include "login-identity-providers.xml" \
    --include "bootstrap.conf"
fi

# Extras úteis (drivers/certs/scripts)
for d in drivers certs scripts; do
  if [[ -d "${NIFI_BASE}/${d}" ]]; then
    echo "-> Backup ${d}/"
    aws s3 sync "${NIFI_BASE}/${d}" "${BUCKET}/${PREFIX_NIFI}/${d}"
  fi
done

if [[ "${SCOPE}" == "full" ]]; then
  # Estado e repositórios
  for d in state flowfile_repository content_repository provenance_repository database_repository logs; do
    if [[ -d "${NIFI_BASE}/${d}" ]]; then
      echo "-> Backup ${d}/"
      aws s3 sync "${NIFI_BASE}/${d}" "${BUCKET}/${PREFIX_NIFI}/${d}"
    fi
  done

  # Registry (se existir)
  if [[ -d "${REG_BASE}" ]]; then
    for d in conf flow_storage database logs; do
      if [[ -d "${REG_BASE}/${d}" ]]; then
        echo "-> Backup Registry ${d}/"
        aws s3 sync "${REG_BASE}/${d}" "${BUCKET}/${PREFIX_REG}/${d}"
      fi
    done
  fi
fi

echo ">> Backup finalizado em: ${BUCKET}/${CLIENT}/backup"