FROM ghcr.io/astral-sh/uv:python3.14-trixie-slim@sha256:b093dbbd7963c765325ecdf866d42915f5327e135569f9dae9c77cac63559bf2 AS build

ARG FETCH_VERSION=2026.11.11
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

RUN uv venv /app/.venv && \
    uv pip install --python /app/.venv/bin/python "mcp-server-fetch==${FETCH_VERSION}"


FROM python:3.14-slim-trixie@sha256:22eafb370920ad8b429e0aec3fff433e0669968519f5d60469d83729c138b28b

COPY --from=build /app/.venv /app/.venv

ENV PATH=/app/.venv/bin:$PATH PYTHONDONTWRITEBYTECODE=1

USER 65534:65534

ENTRYPOINT ["mcp-server-fetch"]
