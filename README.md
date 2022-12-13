# helix-alpha
The provided docker-compose will deploy a sample 3-cluster NATS environment connected to Helix

The deployed NATS instances will be exposed on ports `4222`, `4223`, and `4224` if you wish to query them directly

## Deployment
#### Bring up docker compose
```bash
docker compose up -d
```

#### Connect to Helix UI on port 8080
`http://localhost:8080` or `http://<your_docker_host>:8080`

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
rm -rf nats rna.cue
docker compose up -d
```
