FROM ubuntu:22.04

LABEL maintainer="Corneel"
LABEL description="GitHub Fleet Manager - Automated fleet management"

# Install dependencies
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    jq \
    shellcheck \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy fleet-manager files
COPY . /app

# Make scripts executable
RUN chmod +x scripts/*.sh lib/*.sh github_fleet_manager.sh

# Create necessary directories
RUN mkdir -p /app/logs /app/data /app/backups

# Set environment variables
ENV FLEET_MANAGER_HOME=/app
ENV FLEET_MANAGER_LOGS=/app/logs
ENV FLEET_MANAGER_DATA=/app/data

# Default command
CMD ["bash", "github_fleet_manager.sh", "help"]
