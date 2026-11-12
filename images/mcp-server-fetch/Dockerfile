FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim@sha256:81a1340fea1e72ad4a8e9a016128b0c61041cf182ea49fd788023e52842bc147 AS build

ARG FETCH_VERSION=2026.11.11
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

RUN uv venv /app/.venv && \
    uv pip install --python /app/.venv/bin/python "mcp-server-fetch==${FETCH_VERSION}"


FROM python:3.14-slim-trixie@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f

COPY --from=build /app/.venv /app/.venv

ENV PATH=/app/.venv/bin:$PATH PYTHONDONTWRITEBYTECODE=1

USER 65534:65534

ENTRYPOINT ["mcp-server-fetch"]
