ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE=openc3-ruby

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_IMAGE}:${OPENC3_TAG}

WORKDIR /openc3/

USER ${USER_ID}:${GROUP_ID}

# --chmod=777 sets the mode as the files are copied so we don't need a later
# recursive chmod (which would duplicate the whole tree into its own layer).
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 . .

USER root

RUN mkdir -p lib/openc3/ext \
    && git config --global http.sslCAinfo /devel/cacert.pem \
    && bundle config set --local without 'development test' \
    && bundle install --quiet \
    && rm -f ./*.gem \
    && rake gems \
    && gem install --local ./openc3-*.gem \
    && openc3_gem=$(dirname `gem which openc3`) \
    && ln -s "${openc3_gem}/openc3" "${openc3_gem}/cosmos" \
    && mkdir -p gems \
    && mv ./*.gem gems/. \
    && gem cleanup \
    && rm -rf /usr/local/lib/ruby/gems/*/cache/* /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/* \
    # Make root-created build output (compiled C extensions, moved gems)
    # writable like the rest of the tree. Scoped so it doesn't copy the whole
    # source tree into this layer.
    && chmod -R 777 /openc3/lib /openc3/gems

# PYPI_URL normally arrives as an ENV baked into the openc3-ruby base image,
# which is the only place the build sets it. That breaks down when this image
# is built against a base image that did not see the current .env - a selective
# rebuild of just this image, or a build pointed at a published openc3-ruby -
# and the relock below would then silently target public PyPI. Accept an
# explicit override so the mirror can be supplied here too; leaving it unset
# keeps whatever the base image carries.
ARG PYPI_URL_OVERRIDE=
ENV PYPI_URL=${PYPI_URL_OVERRIDE:-$PYPI_URL}
ENV UV_DEFAULT_INDEX=${PYPI_URL}/simple

# Set when the PYPI_URL mirror is plain HTTP or has a self-signed certificate.
# Each uv step below turns it into UV_INSECURE_HOST for that step only. It stays
# an ARG, never an ENV, so this image does not carry it into every uv call made
# at run time.
ARG OPENC3_PYPI_ALLOW_INSECURE=

WORKDIR /openc3/python

# Install openc3 Python package and dependencies using UV
# Copy dependency files first for better layer caching
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} python/pyproject.toml python/uv.lock python/.python-version ./

# Install dependencies only (cached when deps don't change)
# Seed UV cache to /openc3/uv_cache/ so system wheels are baked into the
# image. At runtime, the operator copies this into /gems/uv/ (the volume)
# so plugins can reuse these wheels without re-downloading.
#
# Deliberately no --mount=type=cache on these uv steps. UV_CACHE_DIR has to
# point at a real layer so the seed ships in the image, and a cache mount never
# lands in one - so a mount here is dead weight (uv writes only to
# UV_CACHE_DIR). Routing the sync through a mount and copying it into the seed
# afterwards would bake wheels from unrelated past builds into the image, which
# is exactly what verify-uv-cache.sh exists to prevent.
#
# uv-mirror-relock (from the base image) rewrites uv.lock to point at PYPI_URL
# when a PyPI mirror is configured, and does nothing otherwise - a frozen sync
# fetches the absolute pythonhosted.org URLs in the lockfile, which no index
# setting can redirect. Relock and sync in one layer so the lockfile the sync
# uses is the one this layer produced, and save that lockfile so the
# application sync below reuses it rather than resolving a second time. A base
# image that predates the helper skips the relock with a warning rather than
# failing the build. UV_INSECURE_HOST is the bare host:port, credentials and
# path stripped, the same host pip trusts when openc3-ruby installs uv.
RUN if [ -n "${OPENC3_PYPI_ALLOW_INSECURE}" ]; then \
      PYPI_HOST="${PYPI_URL#*://}"; PYPI_HOST="${PYPI_HOST%%/*}"; \
      export UV_INSECURE_HOST="${PYPI_HOST##*@}"; \
    fi && \
    if command -v uv-mirror-relock >/dev/null; then \
      UV_CACHE_DIR=/openc3/uv_cache uv-mirror-relock; \
    else \
      echo "--- relock skipped: base image has no uv-mirror-relock (PYPI_URL host ${PYPI_URL##*@})"; \
    fi && \
    UV_CACHE_DIR=/openc3/uv_cache uv sync --frozen --no-dev --no-install-project && \
    cp uv.lock /tmp/uv.lock.relocked

# Copy application code (excluding .venv from source)
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} python/ .

# Install the application itself with dependencies already present.
# The COPY above restored the committed uv.lock over the relocked one, so put
# the saved lockfile back. Relocking again instead could resolve different
# versions than the cached dependency layer if the mirror has changed since.
# pyproject.toml and uv.lock were part of that layer's COPY, so the saved
# lockfile always matches the source tree copied here.
RUN if [ -n "${OPENC3_PYPI_ALLOW_INSECURE}" ]; then \
      PYPI_HOST="${PYPI_URL#*://}"; PYPI_HOST="${PYPI_HOST%%/*}"; \
      export UV_INSECURE_HOST="${PYPI_HOST##*@}"; \
    fi && \
    cp /tmp/uv.lock.relocked uv.lock && rm /tmp/uv.lock.relocked && \
    UV_CACHE_DIR=/openc3/uv_cache uv sync --frozen --no-dev # NOSONAR

WORKDIR /openc3/

RUN mkdir /gems && chown openc3:openc3 /gems \
    && mkdir /plugins && chown openc3:openc3 /plugins \
    && chmod 777 /gems /plugins /openc3

ENV HOME=/openc3
ENV XDG_CACHE_HOME=/tmp/.cache
# Runtime cache = the /gems volume. The init container copies the baked
# /openc3/uv_cache seed (see the uv sync steps above) into here at startup.
# Build-time steps override this per-RUN with UV_CACHE_DIR=/openc3/uv_cache so
# wheels land in the baked seed, not this volume (which is empty until runtime).
ENV UV_CACHE_DIR=/gems/uv/
USER ${USER_ID}:${GROUP_ID}
