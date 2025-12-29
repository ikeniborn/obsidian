FROM denoland/deno:bin AS deno-bin
FROM node:22.14-bookworm-slim

COPY --from=deno-bin /deno /usr/local/bin/deno

WORKDIR /app

RUN apt-get update && \
    apt-get install -y git curl && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/vrtmrz/livesync-serverpeer.git --recursive /app/livesync-serverpeer

WORKDIR /app/livesync-serverpeer
RUN deno task install || deno install --allow-scripts

RUN mkdir -p /app/vault

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["deno", "task", "main"]
