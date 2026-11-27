FROM python:3.14-slim-trixie@sha256:22eafb370920ad8b429e0aec3fff433e0669968519f5d60469d83729c138b28b
 
RUN pip install --no-cache-dir \
      "beets[fetchart]==2.14.1" \
      pillow && \
    rm -rf /root/.cache
 
ENV HOME=/config
ENV BEETSDIR=/config
ENV PYTHONDONTWRITEBYTECODE=1
 
USER 65534:65534
 
ENTRYPOINT ["beet"]
