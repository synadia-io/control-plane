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
  prom_url: "http://prometheus:9090"
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

mkdir -p ${CONFIG_DIR}

NATS_SYSTEMS="\n  nats_systems: ["
for cluster in ${CLUSTERS[*]}; do
  nsc ${NSC_FLAGS} add operator ${cluster} --generate-signing-key
  nsc ${NSC_FLAGS} edit operator --service-url nats://${cluster}:4222
  nsc ${NSC_FLAGS} add account -n SYS
  nsc ${NSC_FLAGS} edit operator --system-account SYS
  nsc ${NSC_FLAGS} add user -a SYS -n sys
  OPERATOR_KEY=$(nsc ${NSC_FLAGS} generate nkey --operator --store 2>&1 |grep '.nk$' |awk '{ print $4 }' |sed "s%^$(pwd)/nats/%%")
  chmod +r ${CONFIG_DIR}/${OPERATOR_KEY}
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
      operator_signing_key_file: "/etc/${OPERATOR_KEY}"
    },
EOF
)
NATS_SYSTEMS+="\n${NATS_SYSTEM}"
done

RNA_CONFIG+="${NATS_SYSTEMS::-1}]\n}"

echo -e "${RNA_CONFIG}" > rna.cue

find ${CONFIG_DIR} -type d -exec chmod 755 {} \;
