# Synadia Control Plane Demo

Synadia Control Plane is distributed as a Docker image and requires a registry credentials.  If you are interested in demoing Synadia Control Plane, please contact `info@synadia.com`

## Prerequisites

Login to the Synadia Docker registry using the credentials that you were given:

```bash
docker login registry.synadia.io
```

## Initial Deployment

The provided docker-compose will deploy a sample 3-cluster NATS environment connected to Synadia Control Plane

The deployed NATS instances will be exposed on ports `4222`, `4223`, and `4224` if you wish to query them directly

1. (Optional) Set the Public URL that you will use to access the demo by updating `syn-cp.yaml`:

    ```yaml
    server:
      # full URL where you will access Control Plane
      url: http://localhost:8080
    ```

2. Bring up the stack

    ```bash
    docker compose up -d
    ```

3. Connect to the Control Plane UI on port 8080

    Navigate to `http://localhost:8080` or `http://<your_docker_host>:8080`

    The first time that Control Plane runs, the admin username/password will be visible in the logs:

    ```bash
    docker compose logs control-plane
    ```

4. Create your first system

    - Create a system with a NATS URL of `nats://localhost:4222` or `nats://<your_docker_host>:4222`
    - Chose `docker` as your platform for provisioning instructions
    - Copy the NATS configuration from step 2 of the provisioning instructions into `conf/nats-a/nats.conf`
    - Copy the Token from step 3 of the provisioning instructions into the value of `token` in `conf/nats-a/`

5. (Optional) Create additional systems - same as step 4, except use:
   
   - NATS URL of `nats://localhost:4223` or `nats://<your_docker_host>:4223` for `nats-b`
   - NATS URL of `nats://localhost:4224` or `nats://<your_docker_host>:4224` for `nats-c`

6. Restart the stack to pick up configuration changes

    ```bash
    docker compose restart
    ``` 

## Upgrade to a new version

```bash
docker compose pull
docker compose up -d
```

## Cleanup

### To stop the environment
```bash
docker compose down
```

### To stop and delete the associated containers and persistent volumes
```bash
docker compose down -v
```

### To destroy the existing environment and spawn a completely fresh one
```
docker compose down -v
docker compose up -d
```
