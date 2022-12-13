#!/bin/bash

cd "$(dirname "${0}")"

CLUSTERS=("nats-a" "nats-b")
CONFIG_DIR="$(pwd)/nats"
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
  env: "local"
  postgres_url: "postgres://helix:helix@localhost:5432/helix"
  prometheus_url: "http://localhost:9090"
  logging: {
    components: {
      auth: {
        level: "warn"
      }
      sql: {
        level: "debug"
      }
    }
  }
EOF
)

if [[ -d ${CONFIG_DIR} ]]; then 
  echo "Config directory exists"
  read -p "Would you like to delete and replace it? (y/N) "
  if [[ ! ${REPLY} =~ ^[Yy] ]]; then
    exit 1
  else
    rm -r ${CONFIG_DIR}
  fi
fi


mkdir -p ${CONFIG_DIR}

NATS_SYSTEMS="\n  nats_systems: ["
for cluster in ${CLUSTERS[*]}; do
  nsc ${NSC_FLAGS} add operator ${cluster}
  nsc ${NSC_FLAGS} edit operator --service-url nats://${cluster}:4222
  nsc ${NSC_FLAGS} add account -n SYS
  nsc ${NSC_FLAGS} edit operator --system-account SYS
  nsc ${NSC_FLAGS} add user -a SYS -n sys
  OPERATOR_NKEY_OUT=$(nsc ${NSC_FLAGS} generate nkey --operator --store 2>&1) 
  OPERATOR_KEY=$(echo "${OPERATOR_NKEY_OUT}" |head -1)
  OPERATOR_KEY_PATH=$(echo "${OPERATOR_NKEY_OUT}" |grep '.nk$' |awk '{ print $4 }' |sed "s%^$(pwd)/nats/%%")
  nsc ${NSC_FLAGS} edit operator --sk ${OPERATOR_KEY}
  chmod +r ${CONFIG_DIR}/${OPERATOR_KEY_PATH}
  chmod +r ${CONFIG_DIR}/nsc/keys/creds/${cluster}/SYS/sys.creds

  mkdir -p ${CONFIG_DIR}/${cluster}
  NATS_CFG=${CONFIG_DIR}/${cluster}/nats-server.conf
  echo "${NATS_SERVER_CONFIG}" > ${NATS_CFG}
  nsc ${NSC_FLAGS} generate config --nats-resolver >> ${NATS_CFG}
  #Update resolver jwt directory to use /data
  sed -i "s%\(dir: \)'./jwt'%\1'/data/jwt'%" ${NATS_CFG}
  sed -i 's%\(allow_delete: \)false%\1true%' ${NATS_CFG}

  NATS_SYSTEM=$(cat <<EOF
    {
      name:                      "${cluster}"
      urls:                      "nats://${cluster}:4222"
      account_server_url:        "nats://${cluster}:4222"
      system_account_creds_file: "/etc/nsc/keys/creds/${cluster}/SYS/sys.creds"
      operator_signing_key_file: "/etc/${OPERATOR_KEY_PATH}"
    },
EOF
)
NATS_SYSTEMS+="\n${NATS_SYSTEM}"
done

RNA_CONFIG+="${NATS_SYSTEMS::-1}]\n}"

echo -e "${RNA_CONFIG}" > rna.cue

find ${CONFIG_DIR} -type d -exec chmod 755 {} \;
