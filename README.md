# Helix Beta

Helix is currently in Private Beta.  If you would like to participate in the Beta program, please contact `info@synadia.com`

Deployment Methods:
- [Kubernetes via Helm](#helm)
- [Docker Compose](#docker-compose)

## Config Generation

The `generate-config.sh` script can do much of the heavy lifting to populate values for your Helix deployment.

This script is intended to be run in a provisioned NSC environment. It can assist in setting up NSC from scratch, but always first attempts to pull creds and signing keys from an existing configuration.

Most prompts will provide a default value in parenthesis. Empty input will select the default value.

The `Encryption Key URL` supports AWS KMS, Azure KeyVault, GCP Cloud KMS, Hashicorp Vault, and base64 formatted URLs.

## Helm

### Generate Helix Configuration

The `--helm` flag will prompt the script to generate two Helm values files

`helix.json` will contain the Helix configuration file, formatted as Helm values

`helix-secrets.json` will contain sensitive Helm values for populating Kubernetes secrets

```
./generate-config.sh --helm

  _  _ ___ _    _____  __   ___ ___  _  _ ___ ___ ___
 | || | __| |  |_ _\ \/ /  / __/ _ \| \| | __|_ _/ __|
 | __ | _|| |__ | | >  <  | (_| (_) | .` | _| | | (_ |
 |_||_|___|____|___/_/\_\  \___\___/|_|\_|_| |___\___|

Synadia Registry Username: synadia
Synadia Registry Password:

Login Successful
Helix Public URL: https://helix.example.com
Encryption Key URL (Empty to generate local key):
Would you like the Helm chart to manage NATS System Credentials? (Yes):
Add NATS System
  NATS System Name (Empty to proceed): nats
  NATS System URLs (Comma delimited): nats://nats-00.example.com,nats://nats-01.example.com
  Account Server URL (Empty for NATS internal resolver):
  Configure with nsc? (Yes):
  Use existing operator? (Yes):
+------------------------------------------------------------------------+
|                               Operators                                |
+-------------+----------------------------------------------------------+
| Name        | Public Key                                               |
+-------------+----------------------------------------------------------+
| my-operator | OCHVDWJQ6WG7DWUW5PJ3UO2VE5KCGRYPVOCGQ4FHMF4XUR2HQOKF3AVE |
+-------------+----------------------------------------------------------+

  Choose Operator (my-operator):
  Use existing system user? (Yes):
+-----------------------------------------------------------------+
|                              Users                              |
+------+----------------------------------------------------------+
| Name | Public Key                                               |
+------+----------------------------------------------------------+
| sys  | UDS5RWNUWLUS5PIL6YHQKTYHLPQLHBG3IG6HBAQNS3NMKA42VHSZKDJ6 |
+------+----------------------------------------------------------+

  Choose System User (sys):
  Use existing operator signing key? (Yes):
+----------------------------------------------------------------------------------------+
|                                    Operator Details                                    |
+-----------------------+----------------------------------------------------------------+
| Name                  | my-operator                                                    |
| Operator ID           | OCHVDWJQ6WG7DWUW5PJ3UO2VE5KCGRYPVOCGQ4FHMF4XUR2HQOKF3AVE       |
| Issuer ID             | OCHVDWJQ6WG7DWUW5PJ3UO2VE5KCGRYPVOCGQ4FHMF4XUR2HQOKF3AVE       |
| Issued                | 2023-03-28 01:31:46 UTC                                        |
| Expires               |                                                                |
| Account JWT Server    | nats://nats-00.example.com,nats://nats-01.example.com          |
| Operator Service URLs | nats://localhost:4222                                          |
|                       | nats://nats-00.example.com                                     |
|                       | nats://nats-01.example.com                                     |
| System Account        | ADVPRCUOC7QCLV32E4ELB5SQ2YDV2MMJPB4LNVQB7ZP2CQHDTSSPNE34 / SYS |
| Require Signing Keys  | false                                                          |
+-----------------------+----------------------------------------------------------------+
| Signing Keys          | OCWUSNZKJECLWBI673H6KP3CAZT5VGN7443XGRFUUVX6TLD7C3TPQUKF       |
+-----------------------+----------------------------------------------------------------+

  Choose Operator Signing Key (OCWUSNZKJECLWBI673H6KP3CAZT5VGN7443XGRFUUVX6TLD7C3TPQUKF):
  Using existing operator signing key
  Using existing user credentials
Add NATS System
  NATS System Name (Empty to proceed):
{
  "helix": {
    "config": {
      "public_url": "https://helix.example.com",
      "nats_systems": [
        {
          "name": "nats",
          "urls": "nats://nats-00.example.com,nats://nats-01.example.com",
          "account_server_url": "nats://nats-00.example.com,nats://nats-01.example.com",
          "system_account_creds_file": "/conf/helix/nsc/nats/sys.creds",
          "operator_signing_key_file": "/conf/helix/nsc/nats/operator.nk"
        }
      ]
    }
  }
}
Write config to file? (Yes):
Config File Path (/helix-beta/helix.json):
Write Helm secrets to file? (Yes):
Config File Path (/helix-beta/helix-secrets.json):
```

### Chart Values

Details in the [values.yaml](https://github.com/ConnectEverything/helm-charts/blob/main/charts/helix/values.yaml)

### Deploy the Helm Chart

```bash
helm repo add synadia https://connecteverything.github.io/helm-charts
helm repo update
helm upgrade --install helix -n helix --create-namespace -f helix.json -f helix-secrets.json synadia/helix
```

### Login Details

On first run, login credentials will be visible in the logs
```
kubectl logs -n helix deployment/helix
```

### (Optional) Kubernetes Ingress

#### Set your ingress values

values.yaml
```
ingress:
  enabled: true
  className: "nginx"
  annotations: {}
  hosts:
    - host: helix.example.com
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - hosts:
      - helix.example.com
        secretName: helix-tls
```

#### Run Helm upgrade

```
helm upgrade --install helix -n helix --create-namespace -f values.yaml -f helix.json -f helix-secrets.json synadia/helix
```

### Uninstall Chart and Purge Data
```
helm uninstall -n helix helix
```

## Docker Compose

### Generate Helix Configuration

This process will create and populate the `conf` directory with Helix config and NATS system credentials and signing keys.

```
./generate-config.sh

  _  _ ___ _    _____  __   ___ ___  _  _ ___ ___ ___
 | || | __| |  |_ _\ \/ /  / __/ _ \| \| | __|_ _/ __|
 | __ | _|| |__ | | >  <  | (_| (_) | .` | _| | | (_ |
 |_||_|___|____|___/_/\_\  \___\___/|_|\_|_| |___\___|

Helix Public URL: https://helix.example.com
Encryption Key URL (Empty to generate local key):
Add NATS System
  NATS System Name (Empty to proceed): nats
  NATS System URLs (Comma delimited): nats://nats-00.example.com,nats://nats-01.example.com
  Account Server URL (Empty for NATS internal resolver):
  Configure with nsc? (Yes):
  Use existing operator? (Yes):
+------------------------------------------------------------------------+
|                               Operators                                |
+-------------+----------------------------------------------------------+
| Name        | Public Key                                               |
+-------------+----------------------------------------------------------+
| my-operator | OCHVDWJQ6WG7DWUW5PJ3UO2VE5KCGRYPVOCGQ4FHMF4XUR2HQOKF3AVE |
+-------------+----------------------------------------------------------+

  Choose Operator (my-operator):
  Use existing system user? (Yes):
+-----------------------------------------------------------------+
|                              Users                              |
+------+----------------------------------------------------------+
| Name | Public Key                                               |
+------+----------------------------------------------------------+
| sys  | UDS5RWNUWLUS5PIL6YHQKTYHLPQLHBG3IG6HBAQNS3NMKA42VHSZKDJ6 |
+------+----------------------------------------------------------+

  Choose System User (sys):
  Use existing operator signing key? (Yes):
+----------------------------------------------------------------------------------------+
|                                    Operator Details                                    |
+-----------------------+----------------------------------------------------------------+
| Name                  | my-operator                                                    |
| Operator ID           | OCHVDWJQ6WG7DWUW5PJ3UO2VE5KCGRYPVOCGQ4FHMF4XUR2HQOKF3AVE       |
| Issuer ID             | OCHVDWJQ6WG7DWUW5PJ3UO2VE5KCGRYPVOCGQ4FHMF4XUR2HQOKF3AVE       |
| Issued                | 2023-03-28 01:31:46 UTC                                        |
| Expires               |                                                                |
| Account JWT Server    | nats://nats-00.example.com,nats://nats-01.example.com          |
| Operator Service URLs | nats://nats-00.example.com                                     |
|                       | nats://nats-01.example.com                                     |
| System Account        | ADVPRCUOC7QCLV32E4ELB5SQ2YDV2MMJPB4LNVQB7ZP2CQHDTSSPNE34 / SYS |
| Require Signing Keys  | false                                                          |
+-----------------------+----------------------------------------------------------------+
| Signing Keys          | OCWUSNZKJECLWBI673H6KP3CAZT5VGN7443XGRFUUVX6TLD7C3TPQUKF       |
+-----------------------+----------------------------------------------------------------+

  Choose Operator Signing Key (OCWUSNZKJECLWBI673H6KP3CAZT5VGN7443XGRFUUVX6TLD7C3TPQUKF):
  Using existing operator signing key
  Using existing user credentials
Add NATS System
  NATS System Name (Empty to proceed):

Write config to file? (Yes):
Config File Path (/helix-beta/conf/helix/helix.json):

```

#### Bring up the stack

```bash
docker compose up -d
```

#### Connect to Helix UI

The web UI will default to port `8080`

If you wish to change this, you can update the host port in the `docker-compose.yaml`

Navigate to `http://localhost:8080` or `http://<your_docker_host>:8080`

The first time that Helix runs, the admin username/password will be visible in the logs:

```bash
docker compose logs helix
```

#### Upgrade to a new image version

```bash
docker compose pull
docker compose up -d
```

## Cleanup

#### To stop the environment
```bash
docker compose down
```

#### To stop and delete the associated containers and persistent volume
```bash
docker compose down -v
```

#### To purge all configuration and data

This will necessitate a re-run of the `generate-config.sh` script if you wish to start a fresh environment

```
docker compose down -v
rm -rf conf
```
