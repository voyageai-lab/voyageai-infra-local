# VoyageAI — Local Infrastructure

Local development infrastructure for the VoyageAI travel planning platform.

## What's Here

| Path | Description |
|------|-------------|
| `docker-compose.yml` | Full-stack Docker Compose (9 services) |
| `.env` | Environment variables (API keys, secrets) |
| `k8s/` | Kubernetes manifests + kind deployment scripts |

## Quick Start

```bash
# Start everything (from this directory)
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f python-worker

# Stop everything
docker compose down
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| `frontend` | 3000 | React app (Nginx) |
| `java-backend` | 8081 | Spring Boot API |
| `python-service` | 8000 | FastAPI AI service |
| `python-worker` | — | Kafka consumer worker |
| `mcp-googlemaps` | — | MCP Google Maps server |
| `kafka` | 9092 | Kafka broker (KRaft) |
| `redis` | 6379 | Redis cache |
| `mongodb` | 27017 | MongoDB document store |
| `mysql` | 3306 | MySQL relational DB |

## Kubernetes (kind)

```bash
# Deploy to local kind cluster
./k8s/deploy-kind.sh

# Teardown
./k8s/teardown-kind.sh
```

## Sibling Repos

This repo expects the following sibling directories:

```
voyageai/
├── voyageai-infra-local/    # (you are here)
├── voyageai-backend/        # Java Spring Boot
├── voyageai-python-service/ # Python AI service
├── voyageai-web/            # React frontend
├── voyageai-docs/           # Teaching docs
└── voyageai-infra-aws/      # AWS CDK (optional)
```
