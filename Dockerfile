ARG PY_VER=3.11.11-slim-bookworm

######################################################################
# Base python layer
######################################################################
FROM python:${PY_VER} AS python-base

ARG SUPERSET_HOME="/app/superset_home"
ENV SUPERSET_HOME=${SUPERSET_HOME}

RUN mkdir -p $SUPERSET_HOME
RUN useradd --user-group -d ${SUPERSET_HOME} -m --no-log-init --shell /bin/bash superset \
    && chmod -R 1777 $SUPERSET_HOME \
    && chown -R superset:superset $SUPERSET_HOME

# Some bash scripts needed throughout the layers
COPY --chmod=755 docker/*.sh /app/docker/

RUN pip install --upgrade uv
#RUN pip install --no-cache-dir --upgrade uv

# Using uv as it's faster/simpler than pip
RUN uv venv /app/.venv
ENV PATH="/app/.venv/bin:${PATH}"

######################################################################
# Python APP common layer
######################################################################
FROM python-base AS python-common

ENV SUPERSET_HOME="/app/superset_home" \
    HOME="/app/superset_home" \
    SUPERSET_ENV="production" \
    FLASK_APP="superset.app:create_app()" \
    PYTHONPATH="/app/pythonpath" \
    SUPERSET_PORT="8088"

# Copy the entrypoints, make them executable in userspace
COPY --chmod=755 docker/entrypoints /app/docker/entrypoints

WORKDIR /app
# Set up necessary directories and user
RUN mkdir -p \
      ${PYTHONPATH} \
      superset/static \
      requirements \
      apache_superset.egg-info \
      requirements \
    && touch superset/static/version_info.json

# Install Playwright and optionally setup headless browsers
ARG INCLUDE_CHROMIUM="false"
ARG INCLUDE_FIREFOX="false"
RUN --mount=type=cache,target=${SUPERSET_HOME}/.cache/uv \
    if [ "$INCLUDE_CHROMIUM" = "true" ] || [ "$INCLUDE_FIREFOX" = "true" ]; then \
        uv pip install playwright && \
        playwright install-deps && \
        if [ "$INCLUDE_CHROMIUM" = "true" ]; then playwright install chromium; fi && \
        if [ "$INCLUDE_FIREFOX" = "true" ]; then playwright install firefox; fi; \
    else \
        echo "Skipping browser installation"; \
    fi

# Copy required files for Python build
COPY pyproject.toml setup.py MANIFEST.in README.md ./
COPY scripts/check-env.py scripts/

# keeping for backward compatibility
COPY --chmod=755 ./docker/entrypoints/run-server.sh /usr/bin/

# Some debian libs
RUN /app/docker/apt-install.sh \
      curl \
      libsasl2-dev \
      libsasl2-modules-gssapi-mit \
      libpq-dev \
      libecpg-dev \
      libldap2-dev


# TODO, when the next version comes out, use --exclude superset/translations
COPY superset superset
# TODO in the meantime, remove the .po files
RUN rm superset/translations/*/*/*.po

HEALTHCHECK CMD /app/docker/docker-healthcheck.sh
CMD ["/app/docker/entrypoints/run-server.sh"]
EXPOSE ${SUPERSET_PORT}

######################################################################
# Dev image...
######################################################################
FROM python-common AS dev

# Debian libs needed for dev
RUN /app/docker/apt-install.sh \
    git \
    pkg-config \
    default-libmysqlclient-dev

# Copy development requirements and install them
COPY requirements/*.txt requirements/
# Install Python dependencies using docker/pip-install.sh
RUN --mount=type=cache,target=${SUPERSET_HOME}/.cache/uv \
    /app/docker/pip-install.sh --requires-build-essential -r requirements/development.txt
# Install the superset package
RUN --mount=type=cache,target=${SUPERSET_HOME}/.cache/uv \
    uv pip install .

RUN uv pip install .[postgres]
RUN python -m compileall /app/superset

USER superset

CMD ["/app/docker/entrypoints/docker-ci.sh"]
