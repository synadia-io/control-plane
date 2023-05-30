#!/bin/bash

# Generates a config file for Synadia Control Plane

ADVANCED="false"
HELM="false"
HELM_MANAGED_SECRETS="true"
REGISTRY_URL="https://registry.helix-dev.synadia.io"
NGS_KEY_ID="ODLC22NIQQ5U4J6ZDTVOFKTEX4F77E7TVM2RHWSG7N266YOVKTRI4EWX"

regex_keys='^((awskms|gcpkms|azurekeyvault|hashivault|base64key):\/\/)'
regex_loglevel='^(trace|debug|info|warn|error|fatal|panic)$'
regex_nats_urls='^(nats://[^[:space:],]+)(,[[:space:]]*nats://[^[:space:],]+)*$'
regex_url='^https?://([a-zA-Z0-9.-]+)(:[0-9]+)?(/.*)?$'
regex_yn='^[yYnN]'

config={}
secrets={}

local_config_directory="$(pwd)/conf/syn-cp"
container_config_directory="/etc/syn-cp"
config_file_name="syn-cp.json"
secrets_file_name="syn-cp-secrets.json"

check_dependencies() {
    bins=(
        "jq"
        "nsc"
    )

    for bin in "${bins[@]}"; do
        command -v "${bin}" > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            echo "Error: ${bin} is required to run this script" >&2
            exit 1
        fi
    done
}

prompt () {
    prompt="$1"
    regex=${2:-'.*'}
    allow_empty="${3:-"false"}"
    default="${4:-""}"
    password="${5:-"false"}"

    prompt_text="${prompt}"

    if [[ -n ${default} ]]; then
        prompt_text="${prompt_text} (${default})"
    fi

    while true; do
        FLAGS="-p"
        if [[ "${password}" == "true" ]]; then
            FLAGS="-s ${FLAGS}"
        fi
        read ${FLAGS} "${prompt_text}: " input
        input=$(echo "${input}" | tr -d '[:space:]')
        if [[ -z "${input}" && "${allow_empty}" == "true" ]]; then
            echo ${default}
            break
        fi
        if [[ -z "${input}" ]]; then
            continue
        fi
        if [[ "${input}" =~ ${regex} ]]; then
            echo ${input}
            break
        fi
        echo "Invalid Input" >&2
    done

    if [[ "${password}" == "true" ]]; then
        echo "" >&2
    fi
}

create_object_at_path() {
    path="$1"
    object="$2"

    if [[ -n ${path} && "${path}" =~ ^\. ]]; then
        path=${path#.}
    fi

    jsonpath=$(echo "${path}" | jq -R 'split(".")')

    type=$(echo "${object}" | jq -r --argjson path "$jsonpath" 'getpath($path) | type')
    if [[ "${type}" == "null" ]]; then
        parentpath=$(echo "${path}" | awk -F. '{OFS="."; NF--; print}')
        if [[ -n "${parentpath}" ]]; then
            parentjsonpath=$(echo "${parentpath}" | jq -R 'split(".")')
            parenttype=$(echo "${object}" | jq -r --argjson path "$parentjsonpath" 'getpath($path) | type')
            if [[ "${parenttype}" == "null" ]]; then
                subobject=$(create_object_at_path "${parentpath}" "${object}")
            fi
        fi
        object=$(echo "${object}" | jq --argjson path "$jsonpath" 'setpath($path; {})')
    elif [[ "${type}" != "object" ]]; then
        echo "Value at path is not an object" >&2
        echo "${object}"
        return 1
    fi

    echo "${object}"
}

add_kv_to_object() {
    key="$1"
    value="$2"
    object="$3"
    path="${4}" # Dot-separated path. Root if not set

    if [[ -n ${path} && "${path}" =~ ^\. ]]; then
        path=${path#.}
    fi

    object=$(create_object_at_path "${path}" "${object}")
    if [[ $? -ne 0 ]]; then
        echo "${object}"
        return 1
    fi

    if [[ -z ${path} ]]; then
        updated=$(echo "${object}" | jq --arg key "$key" --arg value "$value" '. += {($key): $value}')
    else
        jsonpath=$(echo "${path}" | jq -R 'split(".")')
        updated=$(echo "${object}" | jq --arg key "$key" --arg value "$value" --argjson path "$jsonpath" 'setpath($path; (getpath($path) // {}) + {($key): $value})')
    fi

    if [[ $? -ne 0 ]]; then
        echo "Error adding kv pair to object" >&2
        echo "${object}"
        return 1
    fi

    echo "${updated}"
}

add_kv_bool_to_object() {
    key="$1"
    value=$2
    object="$3"
    path="${4}" # Dot-separated path. Root if not set

    if [[ -n ${path} && "${path}" =~ ^\. ]]; then
        path=${path#.}
    fi

    object=$(create_object_at_path "${path}" "${object}")
    if [[ $? -ne 0 ]]; then
        echo "${object}"
        return 1
    fi

    if [[ -z ${path} ]]; then
        updated=$(echo "${object}" | jq --arg key "$key" --argjson value $value '. += {($key): $value}')
    else
        jsonpath=$(echo "${path}" | jq -R 'split(".")')
        updated=$(echo "${object}" | jq --arg key "$key" --argjson value $value --argjson path "$jsonpath" 'setpath($path; (getpath($path) // {}) + {($key): $value})')
    fi

    if [[ $? -ne 0 ]]; then
        echo "Error adding kv pair to object" >&2
        echo "${object}"
        return 1
    fi

    echo "${updated}"
}

add_json_to_object() {
    key="$1"
    json="$2"
    object="$3"
    path="${4}" # Dot-separated path. Root if not set

    if [[ -n ${path} && "${path}" =~ ^\. ]]; then
        path=${path#.}
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

get_nkey_path() {
    base="$1"
    key="$2"

    echo "${base}/keys/${key:0:1}/${key:1:2}/${key}.nk"
}

nsc_table_to_json() {
    command="$1"

    if [[ "${command}" =~ ^describe ]]; then
      echo "'nsc describe' not supported. Use built-in -J flag" >&2
      exit
    fi

    input="$(eval "nsc ${command}" 2>&1)"
    if [[ ! "${input}" =~ ^\+- ]]; then
      echo "{}"
      exit
    fi

    filtered=""
    while IFS= read -r line; do
      filtered+=$(printf "${line}" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g')
      filtered+="\n"
    done <<< "${input}"

    header=$(printf "${filtered}" | sed -n '2p' | awk '{ print $2 }')
    keys=$(printf "${filtered}" | sed -n '4p' | tr -d '[:blank:]' | sed 's/|$//;s/^|//')
    values=$(printf "${filtered}" | sed -n '6,$p' | sed 's/|$//;s/^|//')

    json=[]

    IFS=$'\n'; for line in ${values}; do
      obj={}
      i=1

      setting=$(echo "${line}" | awk -F '|' -v i="${i}" '{ print $i }' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
      if [[ "${setting}" =~ ^\+- || "${setting}" =~ ^$ ]]; then continue; fi

      IFS='\|'; for key in ${keys}; do
        val=$(echo "${line}" | awk -F '|' -v i="${i}" '{ print $i }' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')
        if [[ "${command}" =~ ^env && ${i} -eq 1 ]]; then val=$(echo ${val} | tr -d '[:blank:]'); fi

        if [[ "${val}" == "*" ]]; then
          val="true"
        elif [[ "${val}" =~ ^$|^No$ ]]; then
          val="false"
        fi

        if [[ "${header}" == "Keys" && "${key}" == "Key" ]]; then
          prefix="${val:0:1}"

          case ${prefix} in
            "O")
              obj=$(add_kv_to_object "Type" "operator" "${obj}")
              ;;
            "A")
              obj=$(add_kv_to_object "Type" "account" "${obj}")
              ;;
            "U")
              obj=$(add_kv_to_object "Type" "user" "${obj}")
              ;;
          esac

        fi

        obj=$(add_kv_to_object "${key}" "${val}" "${obj}")

        ((i++))
      done

      json=$(add_json_to_array "${obj}" "${json}")
  done

  add_json_to_object "${header}" "${json}" "{}"
}

nsc_env_exists() {
  eval "nsc_store=$(nsc_table_to_json "env" | jq -r '.NSC[] | select(.Setting == "CurrentStoreDir") | .EffectiveValue')"
  if [[ -z $(ls -A ${nsc_store} 2>/dev/null) ]]; then
    response=$(prompt "  Current nsc store is empty. Initialize new nsc environment?" "${regex_yn}" "true" "Yes")
    if [[ "${response}" =~ ^[yY] ]]; then
      echo "false"
    else
      return 1
    fi
  else
    echo "true"
  fi
}

setup_nsc() {
    system_name="$1"
    server_url="$2"
    account_server_url="$3"

    env_exists=$(nsc_env_exists)
    if [[ $? -ne 0 ]]; then return 1; fi

    if [[ "${env_exists}" != "true" ]]; then nsc init >&2; fi
    if [[ $? -ne 0 ]]; then return 1; fi

    operators=$(nsc_table_to_json "list operators" | jq -r 'if . == {} then . else .Operators[].Name end')
    operator=""
    system_account=""
    system_account_name=""
    system_user_name=""

    if [[ $(nsc describe operator -J | jq -r '.iss') == "${NGS_KEY_ID}" ]]; then
      operators="{}"
    fi

    new_operator="true"

    eval "nkeys_path=$(nsc_table_to_json "env" | jq -r '.NSC[] | select(.Setting == "$NKEYS_PATH") | .EffectiveValue')"

    if [[ "${operators}" != "{}" ]]; then
        response=$(prompt "  Use existing operator?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            new_operator="false"
            nsc list operators
            while [[ -z "${operator}" ]]; do
                default=$(nsc_table_to_json "env" | jq -r '.NSC[] | select(.Setting == "CurrentOperator") | .EffectiveValue')
                operator=$(prompt "  Choose Operator" "" "true" "${default}")
                nsc describe operator "${operator}" >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then continue; fi
            done

            if [[ "${env_exists}" != "true" ]]; then
              account_server=$(nsc describe operator -J | jq -r '.nats.account_server_url | if . == null then "" else . end')
              service_urls=$(nsc describe operator -n "${operator}" -J | jq -r '.nats.operator_service_urls[0] | if . == null then "" else . end')

              if [[ "${account_server}" == "" ]]; then nsc edit operator --account-jwt-server-url "${account_server_url}"; fi
              if [[ "${service_urls}" == "" || "${service_urls}" == "nats://localhost:4222" ]]; then nsc edit operator --service-url "${server_url}"; fi
            fi
        fi
    fi

    if [[ "${new_operator}" == "true" ]]; then
        response=$(prompt "  Create New Operator?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            operator_name=$(prompt "  Operator Name" "" "true" "${system_name}")
            nsc add operator -n "${operator_name}"
            nsc edit operator --service-url "${server_url}"
            nsc edit operator --account-jwt-server-url "${account_server_url}"
            operator="${operator_name}"
        else
            echo "  Error: Operator is required" >&2
            exit 1
        fi
    fi

    nsc env -o "${operator}" > /dev/null 2>&1

    system_account=$(nsc describe operator -n "${operator}" -J | jq -r '.nats.system_account | if . == null then "" else . end')
    if [[ -z ${system_account} ]]; then
        response=$(prompt "  Create New System Account?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc add account -n SYS
            nsc edit operator --system-account SYS
            system_account_name="SYS"
        else
            echo "  Error: System Account is required" >&2
            exit 1
        fi
    else
        system_account_name=$(nsc_table_to_json "list accounts" | jq -r '.Accounts[] | select(.PublicKey == "'${system_account}'") | .Name')
    fi

    if [[ -z ${system_account_name} ]]; then
        echo "  Error: Unable to determine system account name" >&2
        exit 1
    fi

    nsc env -a "${system_account_name}" > /dev/null 2>&1

    user_list=$(nsc_table_to_json "list users" | jq -r '.Users[].Name')

    if [[ -n ${user_list} ]]; then
        response=$(prompt "  Use existing system user?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc list users >&2
            while [[ -z "${system_user_name}" ]]; do
                default=$(echo "${user_list}" | head -1)
                system_user_name=$(prompt "  Choose System User" "" "true" "${default}")
                system_user_name=$(echo "${user_list}" | grep "^${system_user_name}$")
            done
        fi
    else
        response=$(prompt "  Create New System User?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            system_user_name=$(prompt "  System User Name" "" "true" "sys")
            nsc add user -a "${system_account_name}" -n "${system_user_name}"
        else
            echo "  Error: System User is required" >&2
            exit 1
        fi
    fi

    operator_signing_key=""
    operator_signing_key_path=""
    operator_signing_keys=$(nsc describe operator -n "${operator}" -J | jq -r '.nats.signing_keys | if . == null then "" else . end')


    if [[ -n ${operator_signing_keys} ]]; then
        response=$(prompt "  Use existing operator signing key?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc describe operator -n "${operator}" >&2
            echo "" >&2
            while [[ -z "${operator_signing_key}" ]]; do
                default=$(nsc describe operator -n "${operator}" -J | jq -r '.nats.signing_keys[]' | head -1)
                operator_signing_key=$(prompt "  Choose Operator Signing Key" "" "true" "${default}")
                operator_signing_key=$(nsc describe operator -n "${operator}" -J | jq -r '.nats.signing_keys[]' | grep "^${operator_signing_key}$")
            done
        fi 
    else
        response=$(prompt "  Generate New Operator Signing Key?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            operator_signing_key=$(nsc generate nkey --operator --store 2>&1 | head -1)
            nsc edit operator --sk "${operator_signing_key}"
        else
            echo "  Error: Operator Signing Key is required" >&2
            exit 1
        fi
    fi

    operator_signing_key_path=$(get_nkey_path "${nkeys_path}" "${operator_signing_key}")
    if [[ -z ${operator_signing_key_path} || ! -f ${operator_signing_key_path} ]]; then
        echo "  Error: Unable to determine operator signing key path" >&2
        exit 1
    else
        echo "  Using existing operator signing key" >&2
        cp "${operator_signing_key_path}" "${local_config_directory}/systems/${system_name}/operator-sk/operator-sk.nk"
    fi

    user_creds_path="${nkeys_path}/creds/${operator}/${system_account_name}/${system_user_name}.creds"

    if [[ ! -f "${user_creds_path}" ]]; then
        response=$(prompt "  Generate New User Credentials?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc generate creds -a "${system_account_name}" -n "${system_user_name}" > "${local_config_directory}/systems/${system_name}/sys-user-creds/sys-user.creds"
        else
            echo "  Error: User Credentials are required" >&2
            exit 1
        fi
    else
        echo "  Using existing user credentials" >&2
        cp "${user_creds_path}" "${local_config_directory}/systems/${system_name}/sys-user-creds/sys-user.creds"
    fi

    if [[ "${new_operator}" == "true" ]]; then
        echo "NATS Server Configuration for Generated Operator: ${operator}" >&2
        nsc generate config --nats-resolver >&2
    fi
}

setup_nats_systems() {
    local systems="{}"

    while true; do
        echo "Add NATS System" >&2

        local system="{}"
        local system_secrets="{}"

        name=$(prompt "  NATS System Name (Empty to proceed)" "" "true")
        if [[ -z "$name" ]]; then
            break
        fi

        urls=$(prompt "  NATS System URLs (Comma delimited)" "${regex_nats_urls}")
        system=$(add_kv_to_object "url" "${urls}" "${system}")

        system_dir="${local_config_directory}/systems/${name}"
        operator_sk_dir="${system_dir}/operator-sk"
        sys_user_dir="${system_dir}/sys-user-creds"

        mkdir -p "${operator_sk_dir}"
        mkdir -p "${sys_user_dir}"

        if [[ "${HELM_MANAGED_SECRETS}" == "false" ]]; then 
            user_creds_secret_name=$(prompt "  Kubernetes Secret Name for ${name} System User Creds" "" "true" "syn-cp-${name}")
            user_creds_key=$(prompt "  Secret Key for System User Creds" "" "true" "sys-user.creds")
            operator_sk_secret_name=$(prompt "  Kubernetes Secret Name for ${name} Operator Signing Key" "" "true" "syn-cp-${name}")
            operator_sk_key=$(prompt "  Secret Key for Operator Signing Key" "" "true" "operator-sk.nk")

            system_secrets=$(add_kv_to_object "secretName" "${user_creds_secret_name}" "${secrets}" ".tls.systemUserCreds")
            system_secrets=$(add_kv_to_object "key" "${user_creds_key}" "${secrets}" ".tls.systemUserCreds")
            system_secrets=$(add_kv_to_object "secretName" "${operator_sk_secret_name}" "${secrets}" ".tls.operatorSigningKey")
            system_secrets=$(add_kv_to_object "key" "${operator_sk_key}" "${secrets}" ".tls.operatorSigningKey")
        else
            response=$(prompt "  Configure with nsc?" "${regex_yn}" "true" "Yes")
            if [[ "${response}" =~ ^[yY] ]]; then
                setup_nsc "${name}" "${urls}" "${account_server_url}"
                if [[ $? -ne 0 ]]; then return 1; fi
            fi
            if [[ ! -f "${sys_user_dir}/sys-user.creds" && "${HELM_MANAGED_SECRETS}" == "true" ]]; then
                system_user_creds_path=$(prompt "  System User Credentials File Path")
                while [[ ! -f "$system_user_creds_path" ]]; do
                    echo "File does not exist" >&2
                    system_user_creds_path=$(prompt "  System User Credentials File Path" "" "true")
                done
                cp "${system_user_creds_path}" "${sys_user_dir}/sys-user.creds"
            fi
            if [[ ! -f "${operator_sk_dir}/operator-sk.nk" && "${HELM_MANAGED_SECRETS}" == "true" ]]; then
                operator_signing_key_path=$(prompt "  Operator Signing Key File Path")
                while [[ ! -f "$operator_signing_key_path" ]]; do
                    echo "File does not exist" >&2
                    operator_signing_key_path=$(prompt "  Operator Signing Key File Path" "" "true")
                done
                cp "${operator_signing_key_path}" "${operator_sk_dir}/operator-sk.nk"
            fi

            if [[ "${HELM}" != "true" && -f "${sys_user_dir}/sys-user.creds" ]]; then
                system=$(add_kv_to_object "system_user_creds_file" "${container_config_directory}/systems/${name}/sys-user-creds/sys-user.creds" "${system}")
            elif [[ "${HELM}" != "true" ]]; then
                echo "  Error: Unable to determine system user credentials file path" >&2
                exit 1
            fi

            if [[ "${HELM}" != "true" && -f "${local_config_directory}/systems/${name}/operator-sk/operator-sk.nk" ]]; then
                system=$(add_kv_to_object "operator_signing_key_file" "${container_config_directory}/systems/${name}/operator-sk/operator-sk.nk" "${system}")
            elif [[ "${HELM}" != "true" ]]; then
                echo "  Error: Unable to determine operator signing key file path" >&2
                exit 1
            fi

            response=$(prompt "  Setup NATS mTLS?" "${regex_yn}" "true" "No")
            if [[ "${response}" =~ ^[yY] ]]; then
                if [[ "${HELM}" != "true" ]]; then
                    tls_directory="${local_config_directory}/systems/${name}/cert"
                    mkdir -p  ${tls_directory}
                    cert_file=$(prompt "  Client Certificate File Path" "" "false")
                    while [[ ! -f ${cert_file} ]]; do
                        echo "  Error: File does not exist: ${cert_file}" >&2
                        cert_file=$(prompt "  Client Certificate File Path" "" "false")
                    done
                    key_file=$(prompt "  Client Key File Path" "" "false")
                    while [[ ! -f ${key_file} ]]; do
                        echo "  Error: File does not exist: ${key_file}" >&2
                        key_file=$(prompt "  Client Key File Path" "" "false")
                    done
                    ca_file=$(prompt "  CA File Path" "" "false")
                    while [[ ! -f ${ca_file} ]]; do
                        echo "  Error: File does not exist: ${ca_file}" >&2
                        ca_file=$(prompt "  CA File Path" "" "false")
                    done

                    cp "${cert_file}" "${tls_directory}/client.crt"
                    cp "${key_file}" "${tls_directory}/client.key"
                    cp "${ca_file}" "${tls_directory}/ca.crt"
                    system=$(add_kv_to_object "cert_file" "/etc/syn-cp/systems/${name}/cert/client.crt" "${system}" ".tls")
                    system=$(add_kv_to_object "key_file" "/etc/syn-cp/systems/${name}/cert/client.key" "${system}" ".tls")
                    system=$(add_kv_to_object "ca_file" "/etc/syn-cp/systems/${name}/cert/ca.crt" "${system}" ".tls")
                else
                    secret_name=$(prompt "  Kubernetes Secret Name for ${name} mTLS Certs" "" "false")
                    cert_key=$(prompt "  Secret Key for Certificate" "" "false")
                    key_key=$(prompt "  Secret Key for Certificate Key" "" "false")
                    ca_key=$(prompt "  Secret Key for CA" "" "false")

                    system_secrets=$(add_kv_to_object "secretName" "${secret_name}" "${system_secrets}" ".tls")
                    system_secrets=$(add_kv_to_object "cert" "${cert_key}" "${system_secrets}" ".tls")
                    system_secrets=$(add_kv_to_object "key" "${key_key}" "${system_secrets}" ".tls")
                    system_secrets=$(add_kv_to_object "ca" "${ca_key}" "${system_secrets}" ".tls")
                    system_secrets=$(add_kv_bool_to_object "enabled" true "${system_secrets}" ".tls")
                fi
            fi
        fi

        if [[ "${HELM}" == "true" && ${HELM_MANAGED_SECRETS} == "true" ]]; then
            system_secrets=$(setup_system_secrets "${name}" "${system_secrets}")
        fi

        systems=$(add_json_to_object "system" "${system}" "${systems}" ".${name}")
        systems=$(add_json_to_object "secrets" "${system_secrets}" "${systems}" ".${name}")

    done

    echo "${systems}"
}

setup_system_secrets() {
    local name=$1
    local secrets="$2"

    operator_signing_key=$(cat ${local_config_directory}/systems/${name}/operator-sk/operator-sk.nk)
    system_user_creds=$(cat ${local_config_directory}/systems/${name}/sys-user-creds/sys-user.creds)

    secrets=$(add_kv_to_object "contents" "${operator_signing_key}" "${secrets}" ".operatorSigningKey")
    secrets=$(add_kv_to_object "contents" "${system_user_creds}" "${secrets}" ".systemUserCreds")

    echo "${secrets}"
}

setup_registry_credentials() {
    image_credentials="{}"

    username=$(prompt "Synadia Registry Username")
    password=$(prompt "Synadia Registry Password" "" "false" "" "true")

    auth_token=$(echo -n "${username}:${password}" | base64 | tr -d '\n')

    response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Basic ${auth_token}" "${REGISTRY_URL}/v2/")

    if [[ "${response}" != "200" ]]; then
        echo -e "\n\nInvalid credentials" >&2
        exit 1
    else
        echo -e "\n\nLogin Successful" >&2
    fi

    image_credentials=$(add_kv_to_object "username" "${username}" "${image_credentials}")
    image_credentials=$(add_kv_to_object "password" "${password}" "${image_credentials}")

    echo "${image_credentials}"
}

setup_ingress() {
    url="$1"
    ingress="{}"

    hostname=$(echo ${url} | awk -F[/:] '{print $4}')

    response=$(prompt "Use Kubernetes Ingress?" "${regex_yn}" "true" "No")
    if [[ "${response}" =~ ^[yY] ]]; then
        ingress=$(add_kv_bool_to_object "enabled" true "${ingress}")
        hostname=$(prompt "Ingress Hostname" "" "true" "${hostname}")
        hostname="[\"${hostname}\"]"
        ingress=$(add_json_to_object "hosts" "${hostname}" "${ingress}")
        ingress_class=$(prompt "Ingress Class (Optional)" "" "true")
        if [[ -n "${ingress_class}" ]]; then
            ingress=$(add_kv_to_object "className" "${ingress_class}" "${ingress}")
        fi
        secret_name=$(prompt "Kubernetes Secret Name for TLS Certs (Optional)" "" "true")
        if [[ -n "${secret_name}" ]]; then
            ingress=$(add_kv_to_object "tlsSecretName" "${secret_name}" "${ingress}")
        fi
    fi

    echo "${ingress}"
}

setup_data_sources() {
    data_sources={}

    response=$(prompt "Use external PostgreSQL?" "${regex_yn}" "true" "No")
    if [[ "${response}" =~ ^[yY] ]]; then
        postgres_dsn=$(prompt "PostgreSQL DSN" "" "true")
        data_sources=$(add_kv_to_object "dsn" "${postgres_dsn}" "${data_sources}" ".postgres")
        if [[ "${HELM}" == "true" ]]; then
            response=$(prompt "Use PostgreSQL mTLS?" "${regex_yn}" "true" "No")
            if [[ "${response}" =~ ^[yY] ]]; then
                secret_name=$(prompt "  Kubernetes Secret Name for PostgreSQL mTLS Certs" "" "false")
                cert_key=$(prompt "  Secret Key for Certificate" "" "false")
                key_key=$(prompt "  Secret Key for Certificate Key" "" "false")
                ca_key=$(prompt "  Secret Key for CA" "" "false")
                if [[ -n ${secret_name} && -n ${cert_key} && -n ${key_key} && -n ${ca_key} ]]; then
                    data_sources=$(add_kv_to_object "secretName" "${secret_name}" "${data_sources}" ".postgres.tls")
                    data_sources=$(add_kv_to_object "cert" "${cert_key}" "${data_sources}" ".postgres.tls")
                    data_sources=$(add_kv_to_object "key" "${key_key}" "${data_sources}" ".postgres.tls")
                    data_sources=$(add_kv_to_object "ca" "${ca_key}" "${data_sources}" ".postgres.tls")
                    data_sources=$(add_kv_bool_to_object "enabled" true "${data_sources}" ".postgres.tls")
                fi
            fi
        fi
    fi

    response=$(prompt "Use external Prometheus?" "${regex_yn}" "true" "No")
    if [[ "${response}" =~ ^[yY] ]]; then
        prometheus_url=$(prompt "Prometheus URL" "" "true")
        data_sources=$(add_kv_to_object "url" "${prometheus_url}" "${data_sources}" ".prometheus")
        bearer_token=$(prompt "Bearer Token (Optional)" "" "true" "")
        if [[ -n ${bearer_token} ]]; then
            data_sources=$(add_kv_to_object "bearer_token" "${bearer_token}" "${data_sources}" ".prometheus")
        else
            username=$(prompt "Username (Optional)" "" "true")
            password=$(prompt "Password (Optional)" "" "false" "" "true")
            if [[ -n ${username} && -n ${password} ]]; then
                data_sources=$(add_kv_to_object "username" "${username}" "${data_sources}" ".prometheus.basic_auth")
                data_sources=$(add_kv_to_object "password" "${password}" "${data_sources}" ".prometheus.basic_auth")
            fi
        fi
        response=$(prompt "Setup Prometheus mTLS?" "${regex_yn}" "true" "No")
        if [[ "${response}" =~ ^[yY] ]]; then
            if [[ "${HELM}" != "true" ]]; then 
                cert_file=$(prompt "Client Certificate File Path" "" "false")
                while [[ ! -f ${cert_file} ]]; do
                    echo "Error: File does not exist: ${cert_file}" >&2
                    cert_file=$(prompt "Client Certificate File Path" "" "false")
                done
                key_file=$(prompt "Client Key File Path" "" "false")
                while [[ ! -f ${key_file} ]]; do
                    echo "Error: File does not exist: ${key_file}" >&2
                    key_file=$(prompt "Client Key File Path" "" "false")
                done
                ca_file=$(prompt "CA File Path" "" "false")
                while [[ ! -f ${ca_file} ]]; do
                    echo "Error: File does not exist: ${ca_file}" >&2
                    ca_file=$(prompt "CA File Path" "" "false")
                done

                cp "${cert_file}" "${tls_directory}/client.crt"
                cp "${key_file}" "${tls_directory}/client.key"
                cp "${ca_file}" "${tls_directory}/ca.crt"
                data_sources=$(add_kv_to_object "cert_file" "/conf/syn-cp/tls/prometheus/client.crt" "${data_sources}" ".prometheus.tls")
                data_sources=$(add_kv_to_object "key_file" "/conf/syn-cp/tls/prometheus/client.key" "${data_sources}" ".prometheus.tls")
                data_sources=$(add_kv_to_object "ca_file" "/conf/syn-cp/tls/prometheus/ca.crt" "${data_sources}" ".prometheus.tls")
            else
                secret_name=$(prompt "  Kubernetes Secret Name for Prometheus mTLS Certs" "" "false")
                cert_key=$(prompt "  Secret Key for Certificate" "" "false")
                key_key=$(prompt "  Secret Key for Certificate Key" "" "false")
                ca_key=$(prompt "  Secret Key for CA" "" "false")
                if [[ -n ${secret_name} && -n ${cert_key} && -n ${key_key} && -n ${ca_key} ]]; then
                    data_sources=$(add_kv_to_object "secretName" "${secret_name}" "${data_sources}" ".prometheus.tls")
                    data_sources=$(add_kv_to_object "cert" "${cert_key}" "${data_sources}" ".prometheus.tls")
                    data_sources=$(add_kv_to_object "key" "${key_key}" "${data_sources}" ".prometheus.tls")
                    data_sources=$(add_kv_to_object "ca" "${ca_key}" "${data_sources}" ".prometheus.tls")
                    data_sources=$(add_kv_bool_to_object "enabled" true "${data_sources}" ".prometheus.tls")
                fi
            fi
        fi
    fi

    echo "${data_sources}"
}

setup_logging() {
    logging={}
    components={}
    default="info"

    component_list="auth api agent audit sql embedded_postgres embedded_prometheus alert_poller encryption_rotator service_observation_poller"

    response=$(prompt "Change default log levels?" "${regex_yn}" "true" "No")
    if [[ "${response}" =~ ^[nN] ]]; then
        return
    fi

    for component in ${component_list}; do
        level=$(prompt "Logging Level for ${component}" "${regex_loglevel}" "true" "${default}")
        if [[ "${level}" != "${default}" ]]; then
            components=$(add_json_to_object "${component}" "{\"level\": \"${level}\"}" "${components}")
        fi
    done

    logging=$(add_json_to_object "components" "${components}" "${logging}")

    echo "${logging}"
}

setup_jobs() {
    jobs={}

    job_list="alert_poller encryption_rotator service_observation_poller"

    response=$(prompt "Change background job defaults?" "${regex_yn}" "true" "No")
    if [[ "${response}" =~ ^[nN] ]]; then
        return
    fi

    for job in ${job_list}; do
        job_json={}
        response=$(prompt "Enable ${job}?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[nN] ]]; then
            job_json=$(add_kv_bool_to_object "enabled" false "${job_json}")
        fi

        if [[ job == "alert_poller" ]]; then
            response=$(prompt "Alert Retention Days? (7)" "^[0-9]+$" "true")
            if [[ -n "${response}" ]]; then
                job_json=$(add_kv_to_object "retention_days" "${response}" "${job_json}")
            fi
        fi

        if [[ job == "encryption_rotator" ]]; then
            response=$(prompt "Encryption Rotation Interval in Days?" "^[0-9]+$" "true")
            if [[ -n "${response}" ]]; then
                job_json=$(add_kv_to_object "rotation_interval" "${response}" "${job_json}")
            fi
        fi

        if [[ "${job_json}" != "{}" ]]; then
            jobs=$(add_json_to_object "${job}" "${job_json}" "${jobs}")
        fi
    done

    echo "${jobs}"
}

prepare_helm_secret_values() {
    systems=$1
    secret_values="{}"

    secret_values=$(jq -r 'with_entries(.value = .value.secrets)' <<< "${systems}")

    add_json_to_object "systems" "${secret_values}" "{}" ".config"
 }

cat << 'EOF'
  ___                   _ _                        
 / __|_  _ _ _  __ _ __| (_)__ _                   
 \__ \ || | ' \/ _` / _` | / _` |                  
 |___/\_, |_||_\__,_\__,_|_\__,_|                  
   ___|__/     _           _   ___ _               
  / __|___ _ _| |_ _ _ ___| | | _ \ |__ _ _ _  ___ 
 | (__/ _ \ ' \  _| '_/ _ \ | |  _/ / _` | ' \/ -_)
  \___\___/_||_\__|_| \___/_| |_| |_\__,_|_||_\___|

EOF

check_dependencies

while [[ $# -gt 0 ]]; do
  case "$1" in
    --advanced)
      ADVANCED=true
      shift
      ;;
    --helm)
      HELM=true
      shift
      ;;
    *)
      echo "Error: Invalid argument: $1"
      exit 1
      ;;
  esac
done

public_url=$(prompt "Control-Plane Public URL" "${regex_url}" "true" "http://localhost:8080")
config=$(add_kv_to_object "url" "${public_url}" "${config}" ".server")

registry_credentials="{}"
ingress="{}"
if [[ "${HELM}" == "true" ]]; then
    registry_credentials=$(setup_registry_credentials)
    if [[ $? -ne 0 ]]; then
        exit $?
    fi
    ingress=$(setup_ingress "${public_url}")
fi

response=$(prompt "Enable Native HTTPS?" "${regex_yn}" "true" "No")
if [[ "${response}" =~ ^[yY] ]]; then
    tls_directory="${local_config_directory}/certs/server"
    mkdir -p  ${tls_directory}

    if [[ "${HELM}" != "true" ]]; then
        cert_file=$(prompt "Certificate File Path" "" "false")
        while [[ ! -f ${cert_file} ]]; do
            echo "Error: File does not exist: ${cert_file}" >&2
            cert_file=$(prompt "Certificate File Path" "" "false")
        done
        key_file=$(prompt "Key File Path" "" "false")
        while [[ ! -f ${key_file} ]]; do
            echo "Error: File does not exist: ${key_file}" >&2
            key_file=$(prompt "Key File Path" "" "false")
        done

        cp "${cert_file}" "${tls_directory}/server.crt"
        cp "${key_file}" "${tls_directory}/server.key"
        config=$(add_kv_to_object "cert_file" "${container_config_directory}/certs/server/server.crt" "${config}" ".server.tls")
        config=$(add_kv_to_object "key_file" "${container_config_directory}/certs/server/server.key" "${config}" ".server.tls")
    else
        tls_secret_name=$(prompt "Kubernetes Secret Name for TLS Cert" "" "false")
        tls_cert_secret_key=$(prompt "Secret Key for TLS Cert" "" "false")
        tls_key_secret_key=$(prompt "Secret Key for TLS Key" "" "false")

        config=$(add_kv_to_object "secretName" "${tls_secret_name}" "${config}" ".server.tls")
        config=$(add_kv_to_object "cert" "${tls_cert_secret_key}" "${config}" ".server.tls")
        config=$(add_kv_to_object "key" "${tls_key_secret_key}" "${config}" ".server.tls")
        config=$(add_kv_bool_to_object "enabled" true "${config}" ".server.tls")
    fi
fi

if [[ "${ADVANCED}" == "true" ]]; then
    http_listen_port=$(prompt "HTTP Listen Port" "^[0-9]+$" "true" "8080")
    config=$(add_kv_to_object "http_addr" ":${http_listen_port}" "${config}" ".server")
    https_listen_port=$(prompt "HTTPS Listen Port" "^[0-9]+$" "true" "8443")
    config=$(add_kv_to_object "https_addr" ":${https_listen_port}" "${config}" ".server")
    mtls_enabled=$(prompt "Disable Internal mTLS?" "${regex_yn}" "true" "No")
    if [[ "${mtls_enabled}" =~ ^[nN] ]]; then
        config=$(add_kv_bool_to_object "mtls_enabled" false "${config}" ".internal_components")
    fi
fi

encryption_key=$(prompt "Encryption Key URL (Empty to generate local key)" ${regex_keys} "true")
if [[ -n "${encryption_key}" ]]; then
    config=$(add_kv_to_object "key_url" "${encryption_key}" "${config}" ".kms")
fi

if [[ "${HELM}" == "true" ]]; then
    response=$(prompt "Would you like the Helm chart to manage NATS System Credentials?" "${regex_yn}" "true" "Yes")
    if [[ "${response}" =~ ^[nN] ]]; then
        HELM_MANAGED_SECRETS="false"
    fi
fi

data_sources=$(setup_data_sources)
if [[ -n ${data_sources} ]]; then
    if [[ "${HELM}" != "true" ]]; then
        key="data_sources"
    else
        key="dataSources"
    fi
    config=$(add_json_to_object "${key}" "${data_sources}" "${config}")
fi

nats_systems=$(setup_nats_systems)
if [[ $? -ne 0 ]]; then
    exit $?
fi
if [[ -n ${nats_systems} ]]; then
    nats_system_list=$(jq -r 'map_values(.system)' <<< "${nats_systems}")
    config=$(add_json_to_object "systems" "${nats_system_list}" "${config}")
fi

if [[ "${HELM}" == "true" ]]; then
    config=$(add_json_to_object "config" "${config}" "{}")
    secrets=$(prepare_helm_secret_values "${nats_systems}")
fi

if [[ "${ADVANCED}" == "true" ]]; then
    jobs=$(setup_jobs)
    if [[ $? -ne 0 ]]; then
        exit $?
    fi
    if [[ -n ${jobs} ]]; then
        config=$(add_json_to_object "jobs" "${jobs}" "${config}")
    fi
fi

if [[ "${ADVANCED}" == "true" ]]; then
    logging=$(setup_logging)
    if [[ $? -ne 0 ]]; then
        exit $?
    fi
    if [[ -n ${logging} ]]; then
        config=$(add_json_to_object "logging" "${logging}" "${config}")
        sleep 2
    fi
fi

if [[ "${registry_credentials}" != "{}" ]]; then
    secrets=$(add_json_to_object "imagePullSecret" "${registry_credentials}" "${secrets}")
fi

if [[ "${ingress}" != "{}" ]]; then
    config=$(add_json_to_object "ingress" "${ingress}" "${config}")
fi

echo "${config}" | jq

config_path="${local_config_directory}"
if [[ "${HELM}" == "true" ]]; then
  config_path="$(pwd)"
fi

response=$(prompt "Write config to file?" "${regex_yn}" "true" "Yes")
if [[ "${response}" =~ ^[yY] ]]; then
    config_file=$(prompt "Config File Path" "" "true" "${config_path}/${config_file_name}")
    if [[ -f "${config_file}" ]]; then
        response=$(prompt "File exists, overwrite?" "${regex_yn}" "true" "No")
        if [[ ! "${response}" =~ ^[yY] ]]; then
            exit 0
        fi
    fi
    echo "${config}" | jq > "${config_file}"
fi

if [[ "${secrets}" != "{}" ]]; then
    response=$(prompt "Write Helm secrets to file?" "${regex_yn}" "true" "Yes")
    if [[ "${response}" =~ ^[yY] ]]; then
      secrets_file=$(prompt "Config File Path" "" "true" "${config_path}/${secrets_file_name}")
        if [[ -f "${secrets_file}" ]]; then
            response=$(prompt "File exists, overwrite?" "${regex_yn}" "true" "No")
            if [[ ! "${response}" =~ ^[yY] ]]; then
                exit 0
            fi
        fi
        echo "${secrets}" | jq > "${secrets_file}"
    fi
fi

if [[ "${HELM}" == "true" ]]; then
cat << 'EOF'
  ___         _        _ _                         
 |_ _|_ _  __| |_ __ _| | |                        
  | || ' \(_-<  _/ _` | | |                        
 |___|_||_/__/\__\__,_|_|_|                        
   ___         _           _   ___ _               
  / __|___ _ _| |_ _ _ ___| | | _ \ |__ _ _ _  ___ 
 | (__/ _ \ ' \  _| '_/ _ \ | |  _/ / _` | ' \/ -_)
  \___\___/_||_\__|_| \___/_| |_| |_\__,_|_||_\___|

EOF

echo "\
helm repo add synadia https://synadia-io.github.io/helm-charts
helm repo update
helm upgrade --install --create-namespace control-plane \\
    -n syn-cp \\
    -f $([[ "${config_file}" == "$(pwd)/${config_file_name}" ]] && echo "${config_file_name}" || echo ${config_file}) \\
    -f $([[ "${secrets_file}" == "$(pwd)/${secrets_file_name}" ]] && echo "${secrets_file_name}" || echo ${secrets_file}) \\
    synadia/control-plane
"

fi
