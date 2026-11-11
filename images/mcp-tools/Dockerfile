FROM node:26.13.0-trixie-slim@sha256:5adad64f9a1fca2d51972caa65983634c8a774eb300d72b20f7f2a0f60368072

RUN apt-get update && \
    apt-get install --no-install-recommends -y git

RUN npm install -g \
      @modelcontextprotocol/server-filesystem@2.0.1 \
      @cyanheads/git-mcp-server@2.15.3 \
 && npm cache clean --force

RUN <<EOF cat > /etc/gitconfig
[credential]
    helper = store --file=/etc/git-credentials
EOF

USER 65534:65534

WORKDIR /workspace
