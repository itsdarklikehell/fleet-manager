#!/usr/bin/env bash
# scripts/setup-docker-container.sh - Docker containerisatie
# Containeriseert de fleet manager voor eenvoudige deployment
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Setup Docker Container ==="

# Configuratie
DOCKER_DIR="docker"
mkdir -p "$DOCKER_DIR"

# Functies
create_dockerfile() {
  local dockerfile="$DOCKER_DIR/Dockerfile"
  
  cat > "$dockerfile" << 'DOCKERFILE'
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    python3 \
    jq \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY scripts/ /app/scripts/
COPY lib/ /app/lib/
COPY .github/ /app/.github/

RUN chmod +x /app/scripts/*.sh /app/lib/*.sh

CMD ["/bin/bash", "-c", "echo Fleet Manager Container Ready && bash scripts/health-check.sh && tail -f /dev/null"]
DOCKERFILE
  
  echo "  ✅ Dockerfile gemaakt"
}

create_docker_compose() {
  local compose_file="$DOCKER_DIR/docker-compose.yml"
  
  cat > "$compose_file" << 'COMPOSE'
version: '3.8'

services:
  fleet-manager:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: fleet-manager
    volumes:
      - ../scripts:/app/scripts
      - ../lib:/app/lib
      - ../.github:/app/.github
      - fleet-data:/app/data
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}
      - TELEGRAM_TOKEN=${TELEGRAM_TOKEN}
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    container_name: fleet-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: fleet-grafana
    ports:
      - "3000:3000"
    volumes:
      - ../lib/grafana/dashboards:/etc/grafana/dashboards
      - ../lib/grafana/datasources:/etc/grafana/datasources
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
    restart: unless-stopped

volumes:
  fleet-data:
COMPOSE
  
  echo "  ✅ Docker Compose gemaakt"
}

create_prometheus_config() {
  local prom_config="$DOCKER_DIR/prometheus.yml"
  
  cat > "$prom_config" << 'PROM'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'fleet-manager'
    static_configs:
      - targets: ['fleet-manager:9122']
PROM
  
  echo "  ✅ Prometheus config gemaakt"
}

# Hoofdlogica
create_dockerfile
create_docker_compose
create_prometheus_config

echo ""
echo "✅ Docker containerisatie setup klaar"
