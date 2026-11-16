ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE=openc3-ruby

# Layers, ordered so the most frequently edited inputs invalidate the least.
# A change to the input rebuilds that layer and every layer after it in its
# stage. [P1], [F3] etc. tag the instructions below that build each layer.
#
# python-build stage (output merged into the final image)
#   [P1] Python dependencies     <- python/pyproject.toml, uv.lock, .python-version
#   [P2] Python project install  <- python/
#
# Final stage
#   [F1] C extension sources     <- ext/
#   [F2] Gem dependencies        <- Gemfile, Gemfile.lock, openc3.gemspec
#   [F3] Application source      <- Guardfile ... lib/, least to most edited
#   [F4] Gem build and install   <- [F3] (compiles the C extensions into the
#                                    installed gem and into lib/)
#   [F5] Python merge            <- python-build output
#   [F6] Runtime dirs, env, user
#
FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_IMAGE}:${OPENC3_TAG} AS python-build

# Python and Ruby build in separate stages and are merged at the end, so a
# python/ edit never reruns the Ruby build and vice versa.
WORKDIR /openc3/

USER root

# PYPI_URL is normally baked into the openc3-ruby base image. If this image is
# built against a base that missed the current .env, the relock below would
# silently target public PyPI, so accept an explicit override. Unset keeps the
# base image's value.
ARG PYPI_URL_OVERRIDE=
ENV PYPI_URL=${PYPI_URL_OVERRIDE:-$PYPI_URL}
ENV UV_DEFAULT_INDEX=${PYPI_URL%/}/simple

# Set when the PYPI_URL mirror is plain HTTP or self-signed. Each uv step turns
# it into UV_INSECURE_HOST. It stays an ARG so it never reaches run time.
ARG OPENC3_PYPI_ALLOW_INSECURE=

WORKDIR /openc3/python

# [P1] Copy dependency files first so the dependency layer caches.
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} python/pyproject.toml python/uv.lock python/.python-version ./

# [P1] Install dependencies only. The wheels are seeded into /openc3/uv_cache so
# plugins can reuse them; the operator copies it into the /gems/uv volume at
# runtime.
#
# No --mount=type=cache: UV_CACHE_DIR must be a real layer so the seed ships,
# and wheels pulled in from unrelated builds are what verify-uv-cache.sh guards
# against.
#
# uv-mirror-relock (from the base image) points uv.lock at PYPI_URL when a
# mirror is set, since a frozen sync follows the lockfile's absolute
# pythonhosted.org URLs. Relock and sync share a layer, and the relocked
# lockfile is saved for the application sync below. A base image without the
# helper fails the build when PYPI_URL is a mirror, and skips the relock for the
# public index.
#
# --no-build runs no third-party setup code: the relock reads wheel metadata
# only, and a mirror serving just an sdist fails the build. The dependency sync
# uses it too, since every locked dependency ships amd64 and arm64 wheels.
#
# The relock uses a throwaway cache because it resolves dev groups too, and
# would otherwise seed dev-only wheels into /openc3/uv_cache.
RUN if [ -n "${OPENC3_PYPI_ALLOW_INSECURE}" ]; then \
      PYPI_HOST="${PYPI_URL#*://}"; PYPI_HOST="${PYPI_HOST%%/*}"; \
      export UV_INSECURE_HOST="${PYPI_HOST##*@}"; \
    fi && \
    if command -v uv-mirror-relock >/dev/null; then \
      RELOCK_CACHE="$(mktemp -d)" && \
      UV_CACHE_DIR="${RELOCK_CACHE}" uv-mirror-relock --no-build && \
      rm -rf "${RELOCK_CACHE}"; \
    else \
      case "${PYPI_URL%/}" in \
        ""|https://pypi.org) echo "--- relock skipped: base image has no uv-mirror-relock, PYPI_URL is the public index" ;; \
        *) echo "ERROR: base image has no uv-mirror-relock but PYPI_URL host ${PYPI_URL##*@} is a mirror; rebuild openc3-ruby" >&2; exit 1 ;; \
      esac; \
    fi && \
    UV_CACHE_DIR=/openc3/uv_cache uv sync --frozen --no-dev --no-install-project --no-build && \
    cp uv.lock /tmp/uv.lock.relocked

# [P2] Copy application code (.venv is excluded by .dockerignore)
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} python/ .

# [P2] Install the project itself. The COPY above restored the committed uv.lock, so
# put the saved relocked one back; relocking again could resolve different
# versions if the mirror changed.
#
# No --no-build: uv cannot install the editable openc3 project under it. All
# dependencies are already installed, so the only setup code run is openc3's own.
RUN if [ -n "${OPENC3_PYPI_ALLOW_INSECURE}" ]; then \
      PYPI_HOST="${PYPI_URL#*://}"; PYPI_HOST="${PYPI_HOST%%/*}"; \
      export UV_INSECURE_HOST="${PYPI_HOST##*@}"; \
    fi && \
    cp /tmp/uv.lock.relocked uv.lock && rm /tmp/uv.lock.relocked && \
    UV_CACHE_DIR=/openc3/uv_cache uv sync --frozen --no-dev # NOSONAR

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_IMAGE}:${OPENC3_TAG}

WORKDIR /openc3/

USER root

# [F1] C extension sources first: they change rarely, and the gemspec the
# Gemfile loads lists their extconf.rb files. They are compiled by `gem install`
# in [F4], as before, so the published gem still builds them on install.
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 ext/ ext/

# [F2] Ruby dependencies: only the files that pick the gems, so code edits
# don't reinstall them. The RUN below installs them. 644, not 777 like the
# rest of the tree: these are only read after the build (the API images load
# openc3.gemspec through their Bundler path gem), and the lockfile is frozen.
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=644 Gemfile Gemfile.lock openc3.gemspec ./

RUN git config --global http.sslCAinfo /devel/cacert.pem \
    && bundle config set --local without 'development test' \
    && BUNDLE_FROZEN=true bundle install --quiet

# [F3] Application source, listed by directory (not `COPY . .`) so python/ edits
# don't invalidate the Ruby build. Ordered least to most frequently edited, so
# a lib/ edit leaves the other copies cached. --chmod=777 avoids a later
# recursive chmod that would duplicate the tree in its own layer.
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 .dockerignore Guardfile justfile LICENSE.md Rakefile README.md ./
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 tasks/ tasks/
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 bin/ bin/
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 templates/ templates/
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 data/ data/
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 lib/ lib/

# [F4] Build the openc3 gem from the source above and install it system-wide, with
# a cosmos alias for the old gem name. The built gem is kept in /openc3/gems.
RUN mkdir -p lib/openc3/ext \
    && rm -f ./*.gem \
    && rake gems \
    && gem install --local ./openc3-*.gem \
    # Compile the C extensions into lib/ as well. The API images load openc3 from
    # this source tree as a Bundler path gem, and Bundler does not build
    # extensions for path gems. This runs after 'rake gems' so the compiled
    # files are not packed into the gem.
    && rake build \
    && openc3_gem=$(dirname `gem which openc3`) \
    && ln -s "${openc3_gem}/openc3" "${openc3_gem}/cosmos" \
    && mkdir -p gems \
    && mv ./*.gem gems/. \
    && gem cleanup \
    && rm -rf /usr/local/lib/ruby/gems/*/cache/* /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/* \
    # Root-created build output under lib must be owned by the openc3 user, as in
    # the single-COPY layout. /openc3/gems stays root-owned. Scoped to avoid
    # copying the rest of the source tree into this layer.
    && chown -R ${IMAGE_USER}:${IMAGE_GROUP} /openc3/lib \
    && chmod -R 777 /openc3/lib /openc3/gems

# [F5] Merge in the Python environment and seeded wheel cache. Per-file ownership
# is preserved from python-build: the source is openc3-owned, while the venv and
# cache created by uv as root stay root-owned. /openc3/python itself is re-owned in [F6].
COPY --from=python-build /openc3/python/ /openc3/python/
COPY --from=python-build /openc3/uv_cache/ /openc3/uv_cache/

# [F5] Same override as python-build, redeclared because ENV doesn't carry across
# stages. Baked into the image.
ARG PYPI_URL_OVERRIDE=
ENV PYPI_URL=${PYPI_URL_OVERRIDE:-$PYPI_URL}
ENV UV_DEFAULT_INDEX=${PYPI_URL%/}/simple

# [F6] Runtime directories: /gems and /plugins are volume mount points, writable by
# the openc3 user. /openc3 and /openc3/python are world-writable like the rest
# of the tree, and /openc3/python is owned by openc3 (not recursive: the venv
# stays root-owned).
WORKDIR /openc3/

RUN mkdir /gems && chown ${IMAGE_USER}:${IMAGE_GROUP} /gems \
    && mkdir /plugins && chown ${IMAGE_USER}:${IMAGE_GROUP} /plugins \
    && chown ${IMAGE_USER}:${IMAGE_GROUP} /openc3/python \
    && chmod 777 /gems /plugins /openc3 /openc3/python

# [F6] Runtime environment and the unprivileged user the image runs as.
ENV HOME=/openc3
ENV XDG_CACHE_HOME=/tmp/.cache
# Runtime cache is the /gems volume, seeded from /openc3/uv_cache at startup.
# Build steps override this per RUN so wheels land in the baked seed instead.
ENV UV_CACHE_DIR=/gems/uv/
USER ${USER_ID}:${GROUP_ID}
