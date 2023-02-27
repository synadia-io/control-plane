#!/bin/sh

cd "/conf"

OVERLAY_CONFIG_FILE="helix.json"
RNA_CONFIG_FILE="rna.cue"

CLUSTERS="nats-a nats-b nats-c"
CONFIG_DIR="/conf/helix"
SETUP_DIR="/setup"
NSC_DIR=${CONFIG_DIR}/nsc
NSC_FLAGS="--config-dir=${NSC_DIR} --data-dir=${NSC_DIR}/store --keystore-dir=${NSC_DIR}/keys"
NATS_SERVER_CONFIG=$(cat <<EOF
port: 4222

jetstream {
  store_dir: /data
  max_mem: 0
  max_file: 10GB
}
EOF
)

RNA_CONFIG=$(cat <<EOF
{
  "env": "local",
  "postgres_url": "postgres://helix:helix@localhost:5432/helix",
  "prometheus_url": "http://localhost:9090",
  "logging": {
    "components": {
      "auth": {
        "level": "warn"
      }
    }
  },
EOF
)

overlay () {
  local RNA_CONFIG="$1"

  OVERLAY_CONFIG=$(cat ${SETUP_DIR}/${OVERLAY_CONFIG_FILE} | jq -e 'if . == {} then null else . end')

  if [[ ${?} -gt 1 ]]; then
    echo "Invalid ${OVERLAY_CONFIG_FILE}" >&2
    cleanup
    exit 1
  elif [[ "${OVERLAY_CONFIG}" != "null" ]]; then
    echo -e "Overlaying ${OVERLAY_CONFIG_FILE}" >&2
    echo -e "${RNA_CONFIG}" "${OVERLAY_CONFIG}" | jq -s '.[0] * .[1]'
  fi
}

write_config () {
  echo -e "${RNA_CONFIG}" | jq > "${CONFIG_DIR}/${RNA_CONFIG_FILE}"
}

cleanup () {
  rm -rf ${CONFIG_DIR}
}

if [[ -d ${CONFIG_DIR} ]] && [[ "${1}" == "-s" ]]; then
  echo "Using existing config directory"
  # Apply overlay if present
  if [[ -f ${SETUP_DIR}/${OVERLAY_CONFIG_FILE} ]]; then
    RNA_CONFIG=$(overlay "$(cat "${CONFIG_DIR}/${RNA_CONFIG_FILE}")")
    write_config
  fi
  exit 0
elif [[ -d ${CONFIG_DIR} ]]; then
  if [[ "${1}" != "-f" ]]; then
    echo "Config directory exists"
    read -p "Would you like to delete and replace it? (y/N) "
    if ! echo ${REPLY} | grep -q '^[Yy]'; then
      exit 1
    fi
  fi
  rm -rf ${CONFIG_DIR}
fi

mkdir -p ${CONFIG_DIR}

NATS_SYSTEMS='\n  "nats_systems": ['
for cluster in ${CLUSTERS}; do
  # Create cluster operator
  nsc ${NSC_FLAGS} add operator ${cluster}
  nsc ${NSC_FLAGS} edit operator --service-url nats://${cluster}:4222

  # Add system account
  nsc ${NSC_FLAGS} add account -n SYS
  nsc ${NSC_FLAGS} edit operator --system-account SYS

  # Add system user
  nsc ${NSC_FLAGS} add user -a SYS -n sys

  # Create and associate operator signing key
  OPERATOR_NKEY_OUT=$(nsc ${NSC_FLAGS} generate nkey --operator --store 2>&1)
  OPERATOR_KEY=$(echo "${OPERATOR_NKEY_OUT}" | head -1)
  OPERATOR_KEY_PATH=$(echo "${OPERATOR_NKEY_OUT}" | grep '.nk$' | awk '{ print $4 }')
  nsc ${NSC_FLAGS} edit operator --sk ${OPERATOR_KEY}

  # Create nats server config
  mkdir -p ${CONFIG_DIR}/${cluster}
  NATS_CFG=${CONFIG_DIR}/${cluster}/nats-server.conf
  echo "${NATS_SERVER_CONFIG}" > ${NATS_CFG}
  nsc ${NSC_FLAGS} generate config --nats-resolver >> ${NATS_CFG}

  # Update resolver jwt directory to use /data
  sed -i "s%\(dir: \)'./jwt'%\1'/data/jwt'%" ${NATS_CFG}

  # Update resolver to allow jwt deletion
  sed -i 's%\(allow_delete: \)false%\1true%' ${NATS_CFG}

  # Setup nats server config for RNA
  NATS_SYSTEM=$(cat <<EOF
    {
      "name":                      "${cluster}",
      "urls":                      "nats://${cluster}:4222",
      "account_server_url":        "nats://${cluster}:4222",
      "system_account_creds_file": "${NSC_DIR}/keys/creds/${cluster}/SYS/sys.creds",
      "operator_signing_key_file": "${OPERATOR_KEY_PATH}"
    },
EOF
  )
  # Append nats server config to array
  NATS_SYSTEMS="${NATS_SYSTEMS}\n${NATS_SYSTEM}"
done

# Append nats system array to RNA config
RNA_CONFIG="${RNA_CONFIG}${NATS_SYSTEMS::-1}]\n}"

# Apply overlay if present
if [[ -f ${SETUP_DIR}/${OVERLAY_CONFIG_FILE} ]]; then
  RNA_CONFIG=$(overlay "${RNA_CONFIG}")
fi

# Write out RNA config to file
write_config

# Fail safely if invalid JSON
if [[ ${?} -ne 0 ]]; then
  cleanup
  exit 1
fi


# Ensure directory tree is globally navigable
find ${CONFIG_DIR} -type f -exec chmod 644 {} \;
find ${CONFIG_DIR} -type d -exec chmod 755 {} \;
