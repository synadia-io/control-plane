#!/bin/sh

cd "/conf"

OVERLAY_CONFIG_FILE="syn-cp.json"
CONFIG_FILE="syn-cp.cue"
NEW_INSTALL="true"

CLUSTERS="nats-a nats-b nats-c"
CONFIG_DIR="/conf"
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

CONFIG="{}"

create_object_at_path() {
    path="$1"
    object="$2"

    if [ -n "$path" ]; then
      case "$path" in
        .*)
          path=$(echo "$path" | sed 's/^\.//')
        ;;
      esac
    fi

    jsonpath=$(echo "${path}" | jq -R 'split(".")')

    type=$(echo "${object}" | jq -r --argjson path "$jsonpath" 'getpath($path) | type')

    if [ "${type}" = "null" ]; then
        parentpath=$(echo "${path}" | awk -F. '{OFS="."; NF--; print}')
        if [ -n "${parentpath}" ]; then
            parentjsonpath=$(echo "${parentpath}" | jq -R 'split(".")')
            parenttype=$(echo "${object}" | jq -r --argjson path "$parentjsonpath" 'getpath($path) | type')
            if [ ${parenttype} = "null" ]; then
                subobject=$(create_object_at_path "${parentpath}" "${object}")
            fi
        fi
        object=$(echo "${object}" | jq --argjson path "$jsonpath" 'setpath($path; {})')
    elif [ "${type}" != "object" ]; then
        echo "Value at path is not an object" >&2
        echo "${object}"
        return 1
    fi

    echo "${object}"
}

add_json_to_object() {
    key="$1"
    json="$2"
    object="$3"
    path="${4}" # Dot-separated path. Root if not set

    if [ -n "$path" ]; then
      case "$path" in
        .*)
          path=$(echo "$path" | sed 's/^\.//')
        ;;
      esac
    fi

    object=$(create_object_at_path "${path}" "${object}")
    if [[ $? -ne 0 ]]; then
        echo "${object}"
        return 1
    fi

    if [[ -z ${path} ]]; then
        updated=$(echo "${object}" | jq --arg key "$key" --argjson json "$json" '. += {($key): $json}')
    else
        jsonpath=$(echo "${path}" | jq -R 'split(".")')
        updated=$(echo "${object}" | jq --arg key "$key" --argjson json "$json" --argjson path "$jsonpath" 'setpath($path; (getpath($path) // {}) + {($key): $json})')
    fi

    if [[ $? -ne 0 ]]; then
        echo "Error adding kv pair to object" >&2
        echo "${object}"
        return 1
    fi

    echo "${updated}"
}

add_json_to_array() {
    value="$1"
    array="$2"

    updated=$(echo "${array}" | jq --argjson value "$value" '. += [$value]')

    if [[ $? -ne 0 ]]; then
        echo "Error adding element to array" >&2
        echo "${array}"
        return 1
    fi

    echo "${updated}"
}

overlay () {
  local CONFIG="$1"

  OUT_CONFIG="${CONFIG}"
  OVERLAY_CONFIG=$(cat ${SETUP_DIR}/${OVERLAY_CONFIG_FILE} | jq -e 'if . == {} then null else . end')

  if [[ $? -gt 1 ]]; then
    echo "Invalid ${OVERLAY_CONFIG_FILE}" >&2
    cleanup
    exit 1
  elif [[ "${OVERLAY_CONFIG}" != "null" ]]; then
    echo -e "Overlaying ${OVERLAY_CONFIG_FILE}" >&2
    OUT_CONFIG=$(echo -e "${CONFIG}" "${OVERLAY_CONFIG}" | jq -s '.[0] * .[1]')
    if [[ $? -ne 0 ]]; then
      echo "Overlay Failed" >&2
      OUT_CONFIG="${CONFIG}"
    fi
  fi

  echo "${OUT_CONFIG}"
}

write_config () {
  echo -e "${CONFIG}" | jq > "${CONFIG_DIR}/${CONFIG_FILE}"
}

cleanup () {
  if [ ${NEW_INSTALL} = "true" ]; then
    rm -rf ${CONFIG_DIR}
  fi
}

if [[ -d ${CONFIG_DIR} ]]; then NEW_INSTALL="false"; fi

if [ -f "${CONFIG_DIR}/${CONFIG_FILE}" ] && [ "${1}" = "-s" ]; then
  echo "Using existing config directory"
  # Apply overlay if present
  if [[ -f ${SETUP_DIR}/${OVERLAY_CONFIG_FILE} ]]; then
    CONFIG=$(overlay "$(cat "${CONFIG_DIR}/${CONFIG_FILE}")")
    write_config
  fi
  exit 0
elif [[ -f "${CONFIG_DIR}/${CONFIG_FILE}" ]]; then
  if [[ "${1}" != "-f" ]]; then
    echo "Config exists"
    read -p "Would you like to delete and replace it? (y/N) "
    if ! echo ${REPLY} | grep -q '^[Yy]'; then
      exit 1
    fi
  fi
  rm -rf ${CONFIG_DIR}
fi

mkdir -p ${CONFIG_DIR}

NATS_SYSTEMS="{}"
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
      "url":                      "nats://${cluster}:4222",
      "system_user_creds_file": "${NSC_DIR}/keys/creds/${cluster}/SYS/sys.creds",
      "operator_signing_key_file": "${OPERATOR_KEY_PATH}"
    }
EOF
  )

  # Append nats server config to array
  NATS_SYSTEMS=$(add_json_to_object "${cluster}" "${NATS_SYSTEM}" "${NATS_SYSTEMS}")
done

# Append nats system array to RNA config
CONFIG=$(add_json_to_object "systems" "${NATS_SYSTEMS}" "${CONFIG}")

# Apply overlay if present
if [[ -f ${SETUP_DIR}/${OVERLAY_CONFIG_FILE} ]]; then
  CONFIG=$(overlay "${CONFIG}")
fi

# Write out RNA config to file
write_config

# Fail safely if invalid JSON
if [[ $? -ne 0 ]]; then
  cleanup
  exit 1
fi


# Ensure directory tree is globally navigable
find ${CONFIG_DIR} -type f -exec chmod 644 {} \;
find ${CONFIG_DIR} -type d -exec chmod 755 {} \;
