# helix-alpha
Helix Alpha Install Instructions

## Basic Startup
```bash
#Setup keys and config
./bootstrap.sh

#Start containers
docker-compose up -d

#Generate dev users
docker exec helix-alpha-rna /app/rna dev users
```
