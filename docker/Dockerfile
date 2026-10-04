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
