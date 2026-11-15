FROM node:26.13.1-trixie-slim@sha256:e6bedef217677b276c591795e169840edd9096dbf13f29df8ef8d1856b8820bc

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
