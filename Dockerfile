# syntax=docker/dockerfile:1

# ---- build stage: install dependencies into an isolated virtualenv ----
FROM python:3.13-slim AS build

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build
COPY app/requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --upgrade pip \
 && /opt/venv/bin/pip install -r requirements.txt \
 && /opt/venv/bin/pip uninstall -y pip

# ---- runtime stage: minimal, patched, non-root ----
FROM python:3.13-slim AS runtime

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Pull in Debian security fixes released since the base image was built,
# and remove the base image's own pip (the app never needs it at runtime).
RUN apt-get update \
 && apt-get upgrade -y \
 && rm -rf /var/lib/apt/lists/* \
 && python -m pip uninstall -y pip \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /srv
COPY --from=build /opt/venv /opt/venv
COPY --chown=root:root app/ ./app/

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2).status == 200 else 1)"]

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "app.main:app"]
