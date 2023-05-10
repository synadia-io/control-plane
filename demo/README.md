# Synadia Control Plane Demo

Synadia Control Plane is currently in Private Beta.  If you would like to participate in the Beta program, please contact `info@synadia.com`

## Prerequisites

Login to the Control Plane Beta docker registry using the credentials that you were given:

```bash
docker login registry.helix-dev.synadia.io
```

## Deployment

The provided docker-compose will deploy a sample 3-cluster NATS environment connected to Synadia Control Plane

The deployed NATS instances will be exposed on ports `4222`, `4223`, and `4224` if you wish to query them directly

#### Set Public URL (Optional)
Update `syn-cp.json`:
```
{
  "public_url": "http://control-plane.your-domain.com"
}
```

#### Bring up the stack

```bash
docker compose up -d
```

#### Connect to the Control Plane UI on port 8080

Navigate to `http://localhost:8080` or `http://<your_docker_host>:8080`

The first time that Control Plane runs, the admin username/password will be visible in the logs:

```bash
docker compose logs control-plane
```

#### Upgrade to a new Beta version

```bash
docker compose pull
docker compose up -d
```

## Cleanup

#### To stop the environment
```bash
docker compose down
```

#### To stop and delete the associated containers and persistent volumes
```bash
docker compose down -v
```

#### To destroy the existing environment and spawn a completely fresh one
```
docker compose down -v
docker compose up -d
```
