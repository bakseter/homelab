FROM node:26.13.1-trixie-slim@sha256:abe7e5a82b61a8ef67b315b85497c9e65173387ccf2f4a029248184b8e020be5

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
