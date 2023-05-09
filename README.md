# Synadia Control Plane Beta

Synadia Control Plane is currently in Private Beta.  If you would like to participate in the Beta program, please contact `info@synadia.com`

Deployment Methods:
- [Kubernetes via Helm](#helm)
- [Docker Compose](#docker-compose)

## Config Generation

The `generate-config.sh` script can do much of the heavy lifting to populate values for your Control Plane deployment.

This script is intended to be run in a provisioned NSC environment. It can assist in setting up NSC from scratch, but always first attempts to pull creds and signing keys from an existing configuration.

Most prompts will provide a default value in parenthesis. Empty input will select the default value.

The `Encryption Key URL` supports AWS KMS, Azure KeyVault, GCP Cloud KMS, Hashicorp Vault, and base64 formatted URLs.

## Helm

### Generate Control Plane Configuration

The `--helm` flag will prompt the script to generate two Helm values files

`syn-cp.json` will contain the Control Plane configuration file, formatted as Helm values

`syn-cp-secrets.json` will contain sensitive Helm values for populating Kubernetes secrets

```
./generate-config.sh --helm


  _____   ___  _   _   ___ ___   _      ___ ___  _  _ _____ ___  ___  _      ___ _      _   _  _ ___
 / __\ \ / / \| | /_\ |   \_ _| /_\    / __/ _ \| \| |_   _| _ \/ _ \| |    | _ \ |    /_\ | \| | __|
 \__ \\ V /| .` |/ _ \| |) | | / _ \  | (_| (_) | .` | | | |   / (_) | |__  |  _/ |__ / _ \| .` | _|
 |___/ |_| |_|\_/_/ \_\___/___/_/ \_\  \___\___/|_|\_| |_| |_|_\\___/|____| |_| |____/_/ \_\_|\_|___|

Control-Plane Public URL (http://localhost:8080): https://control-plane.example.com
Synadia Registry Username: synadia
Synadia Registry Password:


Login Successful
Use Kubernetes Ingress? (No): y
Ingress Hostname (control-plane.example.com):
Ingress Class (nginx):
Kubernetes Secret Name for TLS Certs (Optional): syn-cp-tls
Enable HTTPS? (No):
Encryption Key URL (Empty to generate local key):
Would you like the Helm chart to manage NATS System Credentials? (Yes):
Use external PostgreSQL? (No):
Use external Prometheus? (No):
Add NATS System
  NATS System Name (Empty to proceed): nats
  NATS System URLs (Comma delimited): nats://nats-00.example.com,nats://nats-01.example.com
  Configure with nsc? (Yes):
  Use existing operator? (Yes):
+------------------------------------------------------------------------+
|                               Operators                                |
+-------------+----------------------------------------------------------+
| Name        | Public Key                                               |
+-------------+----------------------------------------------------------+
| my-operator | OBCU3CMNCDDEQOI2E7WCILQPERFQLZ4HBPWIAGASJWQCLIJ7XCEJVCTM |
+-------------+----------------------------------------------------------+

  Choose Operator (my-operator):
  Use existing system user? (Yes):
+-----------------------------------------------------------------+
|                              Users                              |
+------+----------------------------------------------------------+
| Name | Public Key                                               |
+------+----------------------------------------------------------+
| sys  | UBEWHIVNTXOYG4JBIJOFA4Y3FFV7ZVS57N4EEYN2LTPTXRRZ7EF3HVNF |
+------+----------------------------------------------------------+

  Choose System User (sys):
  Use existing operator signing key? (Yes):
+----------------------------------------------------------------------------------------+
|                                    Operator Details                                    |
+-----------------------+----------------------------------------------------------------+
| Name                  | my-operator                                                    |
| Operator ID           | OBCU3CMNCDDEQOI2E7WCILQPERFQLZ4HBPWIAGASJWQCLIJ7XCEJVCTM       |
| Issuer ID             | OBCU3CMNCDDEQOI2E7WCILQPERFQLZ4HBPWIAGASJWQCLIJ7XCEJVCTM       |
| Issued                | 2023-05-09 01:41:29 UTC                                        |
| Expires               |                                                                |
| Operator Service URLs | nats://localhost:4222                                          |
|                       | nats://nats-00.example.com                                     |
|                       | nats://nats-01.example.com                                     |
| System Account        | ADVSR6BN47WGWHU7L5FZ3XDJIG2PJ4B3W34HYFAMY64S5ZM7UAJRK3IA / SYS |
| Require Signing Keys  | false                                                          |
+-----------------------+----------------------------------------------------------------+
| Signing Keys          | OB3Z22HD3GQM4WJZDDULKC4FIC37ULCXP2JQSWIBRJ2O6BH463WSOCFN       |
+-----------------------+----------------------------------------------------------------+

  Choose Operator Signing Key (OB3Z22HD3GQM4WJZDDULKC4FIC37ULCXP2JQSWIBRJ2O6BH463WSOCFN):
  Using existing operator signing key
  Using existing user credentials
  Setup NATS mTLS? (No):
Add NATS System
  NATS System Name (Empty to proceed):
{
  "config": {
    "server": {
      "url": "https://control-plane.example.com"
    },
    "dataSources": {},
    "systems": {
      "nats": {
        "url": "nats://nats-00.example.com,nats://nats-01.example.com"
      }
    }
  },
  "ingress": {
    "enabled": true,
    "hosts": [
      "control-plane.example.com"
    ],
    "tlsSecretName": "syn-cp-tls"
  }
}
Write config to file? (Yes):
Config File Path (/syn-cp.json):
Write Helm secrets to file? (Yes):
Config File Path (/syn-cp-secrets.json):


   ___ ___  _  _ _____ ___  ___  _      ___ _      _   _  _ ___   ___ _  _ ___ _____ _   _    _
  / __/ _ \| \| |_   _| _ \/ _ \| |    | _ \ |    /_\ | \| | __| |_ _| \| / __|_   _/_\ | |  | |
 | (_| (_) | .` | | | |   / (_) | |__  |  _/ |__ / _ \| .` | _|   | || .` \__ \ | |/ _ \| |__| |__
  \___\___/|_|\_| |_| |_|_\\___/|____| |_| |____/_/ \_\_|\_|___| |___|_|\_|___/ |_/_/ \_\____|____|

helm repo add synadia https://connecteverything.github.io/helm-charts
helm repo update
helm upgrade --install syn-cp -n syn-cp --create-namespace -f syn-cp.json -f syn-cp-secrets.json synadia/control-plane
```

### Chart Values

Details in the [values.yaml](https://github.com/ConnectEverything/helm-charts/blob/main/charts/control-plane/values.yaml)

### Deploy the Helm Chart

```bash
helm repo add synadia https://connecteverything.github.io/helm-charts
helm repo update
helm upgrade --install syn-cp -n syn-cp --create-namespace -f syn-cp.json -f syn-cp-secrets.json synadia/control-plane
```

### Login Details

On first run, login credentials will be visible in the logs
```
kubectl logs -n syn-cp deployment/syn-cp-control-plane
```

#### Run Helm upgrade

```
helm upgrade --install syn-cp -n syn-cp --create-namespace -f values.yaml -f syn-cp.json -f syn-cp-secrets.json synadia/control-plane
```

### Uninstall Chart and Purge Data
```
helm uninstall -n syn-cp syn-cp
```

## Docker Compose

### Generate Control Plane Configuration

This process will create and populate the `conf` directory with the Control Plane config and NATS system credentials and signing keys.

```
./generate-config.sh


  _____   ___  _   _   ___ ___   _      ___ ___  _  _ _____ ___  ___  _      ___ _      _   _  _ ___
 / __\ \ / / \| | /_\ |   \_ _| /_\    / __/ _ \| \| |_   _| _ \/ _ \| |    | _ \ |    /_\ | \| | __|
 \__ \\ V /| .` |/ _ \| |) | | / _ \  | (_| (_) | .` | | | |   / (_) | |__  |  _/ |__ / _ \| .` | _|
 |___/ |_| |_|\_/_/ \_\___/___/_/ \_\  \___\___/|_|\_| |_| |_|_\\___/|____| |_| |____/_/ \_\_|\_|___|

Control-Plane Public URL (http://localhost:8080): https://control-plane.example.com
Enable HTTPS? (No):  yes
Certificate File Path: tls/cert.pem
Key File Path: tls/key.pem
Encryption Key URL (Empty to generate local key):
Use external PostgreSQL? (No): yes
PostgreSQL DSN: postgresql://username:password@example.com:5432/mydatabase?sslmode=require
Use external Prometheus? (No): yes
Prometheus URL: https://prometheus.example.com
Bearer Token (Optional):
Username (Optional): user
Password (Optional):
Setup Prometheus mTLS? (No):
Add NATS System
  NATS System Name (Empty to proceed): nats
  NATS System URLs (Comma delimited): nats://nats-00.example.com,nats://nats-01.example.com
  Configure with nsc? (Yes):
  Use existing operator? (Yes):
+------------------------------------------------------------------------+
|                               Operators                                |
+-------------+----------------------------------------------------------+
| Name        | Public Key                                               |
+-------------+----------------------------------------------------------+
| my-operator | OBCU3CMNCDDEQOI2E7WCILQPERFQLZ4HBPWIAGASJWQCLIJ7XCEJVCTM |
+-------------+----------------------------------------------------------+

  Choose Operator (my-operator):
  Use existing system user? (Yes):
+-----------------------------------------------------------------+
|                              Users                              |
+------+----------------------------------------------------------+
| Name | Public Key                                               |
+------+----------------------------------------------------------+
| sys  | UBEWHIVNTXOYG4JBIJOFA4Y3FFV7ZVS57N4EEYN2LTPTXRRZ7EF3HVNF |
+------+----------------------------------------------------------+

  Choose System User (sys):
  Use existing operator signing key? (Yes):
+----------------------------------------------------------------------------------------+
|                                    Operator Details                                    |
+-----------------------+----------------------------------------------------------------+
| Name                  | my-operator                                                    |
| Operator ID           | OBCU3CMNCDDEQOI2E7WCILQPERFQLZ4HBPWIAGASJWQCLIJ7XCEJVCTM       |
| Issuer ID             | OBCU3CMNCDDEQOI2E7WCILQPERFQLZ4HBPWIAGASJWQCLIJ7XCEJVCTM       |
| Issued                | 2023-05-09 01:41:29 UTC                                        |
| Expires               |                                                                |
| Operator Service URLs | nats://localhost:4222                                          |
|                       | nats://nats-00.example.com                                     |
|                       | nats://nats-01.example.com                                     |
| System Account        | ADVSR6BN47WGWHU7L5FZ3XDJIG2PJ4B3W34HYFAMY64S5ZM7UAJRK3IA / SYS |
| Require Signing Keys  | false                                                          |
+-----------------------+----------------------------------------------------------------+
| Signing Keys          | OB3Z22HD3GQM4WJZDDULKC4FIC37ULCXP2JQSWIBRJ2O6BH463WSOCFN       |
+-----------------------+----------------------------------------------------------------+

  Choose Operator Signing Key (OB3Z22HD3GQM4WJZDDULKC4FIC37ULCXP2JQSWIBRJ2O6BH463WSOCFN):
  Using existing operator signing key
  Using existing user credentials
  Setup NATS mTLS? (No):
Add NATS System
  NATS System Name (Empty to proceed):
{
  "server": {
    "url": "https://control-plane.example.com",
    "tls": {
      "cert_file": "/etc/syn-cp/certs/server/server.crt",
      "key_file": "/etc/syn-cp/certs/server/server.key"
    }
  },
  "data_sources": {
    "postgres": {
      "dsn": "postgresql://username:password@example.com:5432/mydatabase?sslmode=require
    },
    "prometheus": {
      "url": "https://prometheus.example.com",
      "basic_auth": {
        "username": "user",
        "password": "password"
      }
    }
  },
  "systems": {
    "nats": {
      "url": "nats://nats-00.example.com,nats://nats-01.example.com",
      "system_user_creds_file": "/etc/syn-cp/systems/nats/sys-user-creds/sys-user.creds",
      "operator_signing_key_file": "/etc/syn-cp/systems/nats/operator-sk/operator-sk.nk"
    }
  }
}
Write config to file? (Yes):
Config File Path (/conf/syn-cp/syn-cp.json):
```

#### Bring up the stack

```bash
docker compose up -d
```

#### Connect to the Control Plane UI

The web UI will default to port `8080`

If you wish to change this, you can update the host port in the `docker-compose.yaml`

Navigate to `http://localhost:8080` or `http://<your_docker_host>:8080`

The first time that Control Plane runs, the admin username/password will be visible in the logs:

```bash
docker compose logs control-plane 
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
