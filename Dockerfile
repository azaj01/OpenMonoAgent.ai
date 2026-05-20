# syntax=docker/dockerfile:1.6
#
# OpenMono ACP agent image. Built by the VS Code extension's DockerManager
# (or by the user via `docker build -t openmono/agent:dev public/`) and run
# headless with `--acp-only`. The extension publishes the container's port
# 7475 to a 127.0.0.1 host port and mounts the workspace at /workspace.
#
# The legacy docker/Dockerfile.agent image is the interactive-TUI variant
# wired up by docker/docker-compose.yml; it is unchanged. This Dockerfile
# is what the extension uses.

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Solution-level files for restore layer caching.
COPY Directory.Build.props ./
COPY OpenMono.sln ./
COPY global.json ./

COPY src/OpenMono.Cli/OpenMono.Cli.csproj src/OpenMono.Cli/
RUN dotnet restore src/OpenMono.Cli/OpenMono.Cli.csproj

COPY src/OpenMono.Cli/ src/OpenMono.Cli/
RUN dotnet publish src/OpenMono.Cli/OpenMono.Cli.csproj \
    -c Release \
    -o /app/publish \
    --no-restore \
    /p:UseAppHost=true

# ── Runtime ────────────────────────────────────────────────────────────────
# We need the SDK base because the agent's tools (Bash, Grep, ApplyPatch) shell
# out to git / ripgrep / patch / python and the slim aspnet image doesn't ship
# those. Matching the package set in docker/Dockerfile.agent keeps the two
# images functionally equivalent from the tool registry's point of view.

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ripgrep \
    curl \
    jq \
    tree \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# MCP servers shipped with the agent. Keep in sync with docker/Dockerfile.agent.
RUN pip3 install --no-cache-dir --break-system-packages code-review-graph graphifyy

COPY --from=build /app/publish /usr/local/bin/openmono/
ENV PATH="/usr/local/bin/openmono:${PATH}"

# Sessions live in /data. The caller MUST mount a named volume at /data when
# launching the container (e.g. `-v openmono-sessions-<agent_id>:/data`) for
# session JSON files to survive container removal. The extension's
# DockerManager does this automatically; a user-managed docker-compose setup
# must declare the volume themselves. With `--rm` and an anonymous volume,
# session state is wiped on every container stop.
VOLUME ["/data"]

# Default workspace mount-point. The extension always passes -v <host>:/workspace.
WORKDIR /workspace

# Internal ACP port. The extension maps -p 127.0.0.1:<ephemeral>:7475 on the host;
# inside the container Kestrel binds 0.0.0.0:7475 so the port mapping works.
EXPOSE 7475
ENV ACP_PORT=7475 \
    ASPNETCORE_URLS=http://0.0.0.0:7475

# --acp-only disables the interactive TUI (a detached container has no TTY anyway).
ENTRYPOINT ["openmono", "--acp-only"]
