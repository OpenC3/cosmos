ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE=openc3-ruby

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_IMAGE}:${OPENC3_TAG}

WORKDIR /openc3/

USER ${USER_ID}:${GROUP_ID}

COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} . .

USER root

RUN mkdir -p lib/openc3/ext \
    && git config --global http.sslCAinfo /devel/cacert.pem \
    && bundle config set --local without 'development test' \
    && bundle install --quiet \
    && rake gems \
    && gem install --local ./openc3-*.gem \
    && openc3_gem=$(dirname `gem which openc3`) \
    && ln -s "${openc3_gem}/openc3" "${openc3_gem}/cosmos" \
    && mkdir -p gems \
    && mv ./*.gem gems/. \
    && gem cleanup \
    && rm -rf /usr/lib/ruby/gems/*/cache/* /var/cache/apk/* /tmp/* /var/tmp/*

WORKDIR /openc3/python

# Install openc3 Python package and dependencies using UV
# Copy dependency files first for better layer caching
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} python/pyproject.toml python/uv.lock python/.python-version ./

# Install dependencies only (cached when deps don't change)
# Use build cache mount to avoid re-downloading wheels
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project

# Copy application code (excluding .venv from source)
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} python/ .

# Install the application itself with dependencies already present
# Use build cache mount to avoid re-downloading wheels
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

# Smoke test: verify the package imports correctly
RUN uv run python -Ic 'import openc3; print("openc3 imported successfully")'

WORKDIR /openc3/

RUN mkdir /gems && chown openc3:openc3 /gems \
    && mkdir /plugins && chown openc3:openc3 /plugins \
    && chmod -R 777 /gems/ \
    && chmod -R 777 /plugins/ \
    && chmod -R 777 /openc3/

ENV HOME=/openc3
USER ${USER_ID}:${GROUP_ID}
