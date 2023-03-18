#!/bin/bash

# Generates a config file for Helix

regex_keys='^((awskms|gcpkms|azurekeyvault|hashivault|base64key):\/\/)'
regex_loglevel='^(trace|debug|info|warn|error|fatal|panic)$'
regex_nats_urls='^(nats://[^[:space:],]+)(,[[:space:]]*nats://[^[:space:],]+)*$'
regex_url='^https?://([a-zA-Z0-9.-]+)(:[0-9]+)?(/.*)?$'
regex_yn='^[yYnN]'

config={}

config_directory="$(pwd)/conf/helix"
nsc_directory="${config_directory}/nsc"

check_dependencies() {
    command -v jq > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Error: jq is required to run this script" >&2
        exit 1
    fi
    command -v nsc > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Error: nsc is required to run this script" >&2
        exit 1
    fi
}

prompt () {
    prompt="$1"
    regex=${2:-'.*'}
    allow_empty="${3:-"false"}"
    default="${4:-""}"

    prompt_text="${prompt}"

    if [[ -n ${default} ]]; then
        prompt_text="${prompt_text} (${default})"
    fi

    while true; do
        read -p "${prompt_text}: " input
        input=$(echo "${input}" | tr -d '\n')
        if [[ -z "${input}" && "${allow_empty}" == "true" ]]; then
            echo ${default}
            break
        fi
        if [[ "${input}" =~ ${regex} ]]; then
            echo ${input}
            break
        fi
        if [[ -z "${input}" ]]; then
            continue
        fi
        echo "Invalid Input" >&2
    done
}

add_kv_to_object() {
    key="$1"
    value="$2"
    object="$3"

    updated=$(echo "${object}" | jq --arg key "$key" --arg value "$value" '. + {($key): $value}')

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

    updated=$(echo "${object}" | jq --arg key "$key" --argjson json "$json" '. + {($key): $json}')

    if [[ $? -ne 0 ]]; then
        echo "Error adding json to object" >&2
        echo "${json}" >&2
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

    input="$(eval "nsc ${command}" 2>&1)"

    filtered=""
    while IFS= read -r line; do
      filtered+=$(printf "${line}" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g')
      filtered+="\n"
    done <<< "${input}"

    header=$(printf "${filtered}" | sed -n '2p' |awk '{ print $2 }')
    keys=$(printf "${filtered}" | sed -n '4p' |tr -d '[:blank:]' | sed 's/\|/ /g')
    values=$(printf "${filtered}" |sed -n '6,$p' |tac | sed '1d' |tr -d '[:blank:]')

    json=[]

    for line in ${values}; do
      obj={}
      i=2
      for key in ${keys}; do
        val=$(echo "${line}" | awk -F '|' -v i="${i}" '{ print $i }')
        if [[ "${val}" == "*" ]]; then
          val="true"
        elif [[ "${val}" == "" ]]; then
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

setup_nsc() {
    server_name="$1"
    server_url="$2"
    account_server_url="$3"

    operators=$(nsc_table_to_json "list operators" | jq -r '.Operators[].Name')
    operator=""
    system_account=""
    system_account_name=""
    system_user_name=""

    new_operator="false"

    eval "nkeys_path=$(nsc_table_to_json "env" | jq -r '.NSC[] | select(.Setting == "$NKEYS_PATH") | .EffectiveValue')"

    if [[ -n ${operators} ]]; then
        response=$(prompt "  Use existing operator?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc list operators
            while [[ -z "${operator}" ]]; do
                default=$(nsc_table_to_json "env" | jq -r '.NSC[] | select(.Setting == "CurrentOperator") | .EffectiveValue')
                operator=$(prompt "  Choose Operator" "" "true" "${default}")
                operator=$(echo "${operators}" | grep "^${operator}$")
            done
        else
            new_operator="true"
        fi
    fi

    if [[ ${new_operator} == "true" ]]; then
        response=$(prompt "  Create New Operator?" "${regex_yn}" "true" "No")
        if [[ "${response}" =~ ^[yY] ]]; then
            operator_name=$(prompt "  Operator Name" "" "true" "${server_name}")
            nsc add operator -n "${operator_name}"
            nsc edit operator --service-url "${server_url}"
            nsc edit operator --account-jwt-server-url "${account_server_url}"
            operator="${operator_name}"
        else
            exit 1
        fi
    fi

    nsc env -o "${operator}" > /dev/null 2>&1

    system_account=$(nsc describe operator -n "${operator}" -J | jq -r '.nats.system_account | if . == null then "" else . end')
    if [[ -z ${system_account} ]]; then
        response=$(prompt "  Create New System Account?" "${regex_yn}" "true" "No")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc add account -n SYS
            nsc edit operator --system-account SYS
            system_account_name="SYS"
        else
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
        response=$(prompt "  Create New System User?" "${regex_yn}" "true" "No")
        if [[ "${response}" =~ ^[yY] ]]; then
            system_user_name=$(prompt "  System User Name" "" "true" "sys")
            nsc add user -a "${system_account_name}" -n "${system_user_name}"
        else
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
        response=$(prompt "  Generate New Operator Signing Key?" "${regex_yn}" "true" "No")
        if [[ "${response}" =~ ^[yY] ]]; then
            operator_signing_key=$(nsc generate nkey --operator --store 2>&1 | head -1)
            nsc edit operator --sk "${operator_signing_key}"
        else
            exit 1
        fi
    fi

    operator_signing_key_path=$(get_nkey_path "${nkeys_path}" "${operator_signing_key}")
    if [[ -z ${operator_signing_key_path} || ! -f ${operator_signing_key_path} ]]; then
        echo "  Error: Unable to determine operator signing key path" >&2
        exit 1
    else
        echo "  Using existing operator signing key" >&2
        cp "${operator_signing_key_path}" "${nsc_directory}/${server_name}/operator.nk"
    fi

    user_creds_path="${nkeys_path}/creds/${operator}/${system_account_name}/${system_user_name}.creds"

    if [[ ! -f "${user_creds_path}" ]]; then
        response=$(prompt "  Generate New User Credentials?" "${regex_yn}" "true" "No")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc generate creds -a "${system_account_name}" -n "${system_user_name}" > "${nsc_directory}/${server_name}/sys.creds"
        else
            exit 1
        fi
    else
        echo "  Using existing user credentials" >&2
        cp "${user_creds_path}" "${nsc_directory}/${server_name}/sys.creds"
    fi
}

setup_nats_systems() {
systems=[]
while true; do
    echo "Add NATS System" >&2

    system={}

    name=$(prompt "  NATS System Name (Empty to proceed)" "" "true")
    if [[ -z "$name" ]]; then
        break
    fi

    system=$(add_kv_to_object "name" "${name}" "${system}")

    urls=$(prompt "  NATS System URLs (Comma delimited)" "${regex_nats_urls}")
    system=$(add_kv_to_object "urls" "${urls}" "${system}")

    account_server_url=$(prompt "  Account Server URL (Empty for NATS internal resolver)" "" "true")
    if [[ -z ${account_server_url} ]]; then
        account_server_url="${urls}"
    fi
    system=$(add_kv_to_object "account_server_url" "${account_server_url}" "${system}")

    mkdir -p "${nsc_directory}/${name}"

    response=$(prompt "  Configure with nsc?" "${regex_yn}" "true" "Yes")
    if [[ "${response}" =~ ^[yY] ]]; then
        setup_nsc "${name}" "${urls}" "${account_server_url}"
    fi

    if [[ ! -f "${nsc_directory}/${name}/sys.creds" ]]; then
        system_account_creds_path=$(prompt "  System Account Credentials File Path")
        while [[ ! -f "$system_account_creds_path" ]]; do
            echo "File does not exist" >&2
            system_account_creds_path=$(prompt "  System Account Credentials File Path" "" "true")
        done
        cp "${system_account_creds_path}" "${nsc_directory}/${name}/sys.creds"
    fi
    if [[ ! -f "${nsc_directory}/${name}/operator.nk" ]]; then
        operator_signing_key_path=$(prompt "  Operator Signing Key File Path")
        while [[ ! -f "$operator_signing_key_path" ]]; do
            echo "File does not exist" >&2
            operator_signing_key_path=$(prompt "  Operator Signing Key File Path" "" "true")
        done
        cp "${operator_signing_key_path}" "${nsc_directory}/${name}/operator.nk"
    fi

    if [[ -f "${nsc_directory}/${name}/sys.creds" ]]; then
        system=$(add_kv_to_object "system_account_creds_file" "${nsc_directory}/${name}/sys.creds" "${system}")
    else
        echo "  Error: Unable to determine system account credentials file path" >&2
        exit 1
    fi

    if [[ -f "${nsc_directory}/${name}/operator.nk" ]]; then
        system=$(add_kv_to_object "operator_signing_key_file" "${nsc_directory}/${name}/operator.nk" "${system}")
    else
        echo "  Error: Unable to determine operator signing key file path" >&2
        exit 1
    fi

    systems=$(add_json_to_array "${system}" "${systems}")
done

    echo "${systems}"
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
            job_json=$(add_kv_to_object "enabled" "false" "${job_json}")
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
echo \
'
  _  _ ___ _    _____  __   ___ ___  _  _ ___ ___ ___
 | || | __| |  |_ _\ \/ /  / __/ _ \| \| | __|_ _/ __|
 | __ | _|| |__ | | >  <  | (_| (_) | .` | _| | | (_ |
 |_||_|___|____|___/_/\_\  \___\___/|_|\_|_| |___\___|
'

check_dependencies

mkdir -p "${nsc_directory}"

public_url=$(prompt "Public URL" "${regex_url}")
config=$(add_kv_to_object "public_url" "${public_url}" "${config}")

listen_port=$(prompt "Listen Port" "^[0-9]+$" "true" "8080")
config=$(add_kv_to_object "http_public_addr" ":${listen_port}" "${config}")

response=$(prompt "Would you like to expose metrics?" "${regex_yn}" "true" "No")
if [[ "${response}" =~ ^[yY] ]]; then
    metrics_port=$(prompt "Metrics Port" "^[0-9]+$" "true" "7777")
    config=$(add_kv_to_object "http_metrics_addr" ":${metrics_port}" "${config}")
fi

encryption_key=$(prompt "Encryption Key URL (Empty to generate local key)" ${regex_keys} "true")
if [[ -n "${encryption_key}" ]]; then
    config=$(add_kv_to_object "encryption_key" "${encryption_key}" "${config}")
fi

nats_systems=$(setup_nats_systems)
if [[ $? -ne 0 ]]; then
    exit $?
fi
if [[ -n ${nats_systems} ]]; then
    config=$(add_json_to_object "nats_systems" "${nats_systems}" "${config}")
fi

jobs=$(setup_jobs)
if [[ $? -ne 0 ]]; then
    exit $?
fi
if [[ -n ${jobs} ]]; then
    config=$(add_json_to_object "jobs" "${jobs}" "${config}")
fi

logging=$(setup_logging)
if [[ $? -ne 0 ]]; then
    exit $?
fi
if [[ -n ${logging} ]]; then
    config=$(add_json_to_object "logging" "${logging}" "${config}")
    sleep 2
fi

echo "${config}" |jq

response=$(prompt "Write config to file?" "${regex_yn}" "true" "Yes")
if [[ "${response}" =~ ^[yY] ]]; then
    config_file=$(prompt "Config File Path" "" "true" "helix.json")
    if [[ -f "${config_file}" ]]; then
        response=$(prompt "File exists, overwrite?" "${regex_yn}" "true" "No")
        if [[ ! "${response}" =~ ^[yY] ]]; then
            exit 0
        fi
    fi
    echo "${config}" |jq > "${config_file}"
fi