FROM denoland/deno:bin AS deno-bin
FROM node:22.14-bookworm-slim

COPY --from=deno-bin /deno /usr/local/bin/deno

WORKDIR /app

RUN apt-get update && \
    apt-get install -y git curl procps && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/vrtmrz/livesync-serverpeer.git --recursive /app/livesync-serverpeer

WORKDIR /app/livesync-serverpeer

# Copy and apply patch to fix P2P_Enabled bug
# Bug: globalVariables.set() called BEFORE conf.P2P_Enabled = true
# Fix: Set P2P_Enabled BEFORE globalVariables.set()
COPY fix-p2p-enabled.patch /tmp/
RUN patch -p1 < /tmp/fix-p2p-enabled.patch && rm /tmp/fix-p2p-enabled.patch

RUN deno task install || deno install --allow-scripts

RUN mkdir -p /app/vault

EXPOSE 3000

# ServerPeer is a P2P client, not an HTTP server
# Check if deno process is running instead of HTTP endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD pgrep -f "deno.*main.ts" > /dev/null || exit 1

CMD ["deno", "task", "main"]
