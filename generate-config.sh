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

parse_nsc() {
    command="$1"
    i=${2:-2}
    j=${3:-0}

    out=$(nsc $1 2>&1 | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" |sed -n '6,$p' |tac | sed '1,2d' |tr -d '[:blank:]')

    if [[ j -gt 0 ]]; then
        echo "${out}" |awk -F '|' -v i="${i}" -v j="${j}" '{ print $i" "$j }'  
    else
        echo "${out}" |awk -F '|' -v i="${i}" '{ print $i }'
    fi

}

setup_nsc() {
    server_name="$1"
    server_url="$2"

    command -v nsc > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        return
    fi

    operators=$(parse_nsc "list operators")
    operator=""
    system_account=""
    system_user=""

    new_operator="false"

    eval "nkeys_path=$(parse_nsc "env" 2 4 | grep "\$NKEYS_PATH" |awk '{ print $2 }')"

    if [[ -n ${operators} ]]; then
        response=$(prompt "  Use existing operator?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc list operators
            while [[ -z "${operator}" ]]; do
                local default=$(echo "${operators}" | head -1)
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
            nsc add operator -n "${server_name}"
            nsc edit operator --account-jwt-server-url "${server_url}"
            nsc edit operator --service-url "${server_url}"
            operator="${server_name}"
        fi
    fi

    nsc env -o "${operator}" > /dev/null 2>&1

    system_account=$(nsc describe operator "${operator}" -J | jq -r '.nats.system_account')
    if [[ -z ${system_account} ]]; then
        response=$(prompt "  Create New System Account?" "${regex_yn}" "true" "No")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc add account -n SYS
            nsc edit operator --system-account SYS
            system_account="SYS"
            nsc add user -a SYS -n sys
            system_user="sys"
        fi
    else
        system_account=$(parse_nsc "list accounts" 2 3 | grep "${system_account}$" | awk '{ print $1 }')
    fi

    nsc env -a "${system_account}" > /dev/null 2>&1

    if [[ -z ${system_user} ]]; then
        response=$(prompt "  Use existing system user?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc list users -a "${system_account}"
            while [[ -z "${system_user}" ]]; do
                default=$(parse_nsc "list users" 2 | head -1)
                system_user=$(prompt "  Choose System User" "" "true" "${default}")
                system_user=$(parse_nsc "list users" 2 | grep "^${system_user}$")
            done
        fi
    else
        nsc add user -a "${system_account}" -n sys
        system_user="sys"
    fi

    operator_signing_keys=$(nsc describe operator -n "${operator}" -J | jq -r '.nats.signing_keys[]')
    operator_signing_key_path=""

    if [[ -n ${operator_signing_keys} ]]; then
        response=$(prompt "  Use existing operator signing key?" "${regex_yn}" "true" "Yes")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc describe operator -n "${operator}"
            while [[ -z "${operator_signing_key}" ]]; do
                default=$(nsc describe operator -n "${operator}" -J | jq -r '.nats.signing_keys[]' | head -1)
                operator_signing_key=$(prompt "  Choose Operator Signing Key" "" "true" "${default}")
                operator_signing_key=$(nsc describe operator -n "${operator}" -J | jq -r '.nats.signing_keys[]' | grep "^${operator_signing_key}$")
            done

            operator_signing_key_path="${nkeys_path}/keys/${operator_signing_key:0:1}/${operator_signing_key:1:2}/${operator_signing_key}.nk"

            if [[ -f "${operator_signing_key_path}" ]]; then
                echo "Found Operator Signing Key" >&2
            fi
        fi 
    fi

    if [[ -z "${operator_signing_key_path}" ]]; then
        response=$(prompt "  Generate New Operator Signing Key?" "${regex_yn}" "true" "No")
        if [[ "${response}" =~ ^[yY] ]]; then
            operator_signing_key_path=$(nsc generate nkey --operator --store 2>&1 | grep '.nk$' |awk '{ print $4 }')
        fi
    fi

    cp "${operator_signing_key_path}" "${nsc_directory}/${server_name}/operator.nk"

    user_creds_path="${nkeys_path}/creds/${operator}/${system_account}/${system_user}.creds"

    if [[ -f "${user_creds_path}" ]]; then
        echo "Found System User Credentials" >&2
        cp "${user_creds_path}" "${nsc_directory}/${server_name}/sys.creds"
    else
        response=$(prompt "  Generate New User Credentials?" "${regex_yn}" "true" "No")
        if [[ "${response}" =~ ^[yY] ]]; then
            nsc generate creds -a "${system_account}" -n "${system_user}" > "${nsc_directory}/${server_name}/sys.creds"
        fi
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

    setup_nsc "${name}" "${account_server_url}"

    if [[ -f "${nsc_directory}/${name}/sys.creds" ]]; then
        system=$(add_kv_to_object "system_account_creds_file" "${nsc_directory}/${name}/sys.creds" "${system}")
    fi

    if [[ -f "${nsc_directory}/${name}/operator.nkey" ]]; then
        system=$(add_kv_to_object "operator_signing_key_file" "${nsc_directory}/${name}/operator.nkey" "${system}")
    fi

    if [[ ! -f "${nsc_directory}/${name}/sys.creds" ]]; then
        system_account_creds_file=$(prompt "  System Account Credentials File Path")
        while [[ ! -f "$system_account_creds_file" ]]; do
            echo "File does not exist" >&2
            system_account_creds_file=$(prompt "  System Account Credentials File Path" "" "true")
        done
    fi
    if [[ ! -f "${nsc_directory}/${name}/operator.nkey" ]]; then
        operator_signing_key_file=$(prompt "  Operator Signing Key File Path")
        while [[ ! -f "$operator_signing_key_file" ]]; do
            echo "File does not exist" >&2
            operator_signing_key_file=$(prompt "  Operator Signing Key File Path" "" "true")
        done
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

mkdir -p $(pwd)/conf/helix/nsc

public_url=$(prompt "Public URL" "${regex_url}")
config=$(add_kv_to_object "public_url" "${public_url}" "${config}")

listen_port=$(prompt "Listen Port" "^[0-9]+$" "true" "8080")
config=$(add_kv_to_object "http_public_addr" ":${listen_port}" "${config}")

response=$(prompt "Would you like to expose metrics? (y/N)" "${regex_yn}" "true" "No")
if [[ "${response}" =~ ^[yY] ]]; then
    metrics_port=$(prompt "Metrics Port" "^[0-9]+$" "true" "7777")
    config=$(add_kv_to_object "http_metrics_addr" ":${metrics_port}" "${config}")
fi

encryption_key=$(prompt "Encryption Key URL (Empty to generate local key)" ${regex_keys} "true")
if [[ -n "${encryption_key}" ]]; then
    config=$(add_kv_to_object "encryption_key" "${encryption_key}" "${config}")
fi

nats_systems=$(setup_nats_systems)
if [[ -n ${nats_systems} ]]; then
    config=$(add_json_to_object "nats_systems" "${nats_systems}" "${config}")
fi

jobs=$(setup_jobs)
if [[ -n ${jobs} ]]; then
    config=$(add_json_to_object "jobs" "${jobs}" "${config}")
fi

logging=$(setup_logging)
if [[ -n ${logging} ]]; then
    config=$(add_json_to_object "logging" "${logging}" "${config}")
fi

echo "${config}" |jq