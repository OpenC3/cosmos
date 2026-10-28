ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE=openc3-ruby

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

# Copy dependency files first so the dependency layer caches.
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} python/pyproject.toml python/uv.lock python/.python-version ./

# Install dependencies only. The wheels are seeded into /openc3/uv_cache so
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

# Copy application code (.venv is excluded by .dockerignore)
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} python/ .

# Install the project itself. The COPY above restored the committed uv.lock, so
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

# C extensions first: they change rarely and are the slowest Ruby build step.
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 ext/ ext/

# Compile the extensions into lib/openc3/ext, as `rake build` does. They ship
# from there; OPENC3_PREBUILT_EXT stops the gemspec compiling them again in
# `gem install`. It is set per RUN, not ENV, so it stays out of the image.
RUN mkdir -p lib/openc3/ext \
    && for dir in ext/openc3/ext/*/; do \
         [ -f "$dir/extconf.rb" ] || continue; \
         name=$(basename "$dir") \
         && (cd "$dir" && ruby extconf.rb && make \
             && cp "$name.so" /openc3/lib/openc3/ext/ \
             && rm -f *.o *.so *.def Makefile mkmf.log) \
         || exit 1; \
       done

# Ruby dependencies: only the files that pick the gems, so code edits don't
# reinstall them.
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 Gemfile openc3.gemspec ./

RUN git config --global http.sslCAinfo /devel/cacert.pem \
    && bundle config set --local without 'development test' \
    && OPENC3_PREBUILT_EXT=1 bundle install --quiet

# Application source, listed by directory (not `COPY . .`) so python/ edits
# don't invalidate the Ruby build. Ordered least to most frequently edited, so
# a lib/ edit leaves the other copies cached. --chmod=777 avoids a later
# recursive chmod that would duplicate the tree in its own layer.
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 Guardfile LICENSE.md Rakefile README.md ./
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 tasks/ tasks/
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 bin/ bin/
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 templates/ templates/
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 data/ data/
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 lib/ lib/

RUN rm -f ./*.gem \
    && OPENC3_PREBUILT_EXT=1 rake gems \
    && gem install --local ./openc3-*.gem \
    && openc3_gem=$(dirname `gem which openc3`) \
    && ln -s "${openc3_gem}/openc3" "${openc3_gem}/cosmos" \
    && mkdir -p gems \
    && mv ./*.gem gems/. \
    && gem cleanup \
    && rm -rf /usr/local/lib/ruby/gems/*/cache/* /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/* \
    # Make root-created build output writable. Scoped to avoid copying the
    # source tree into this layer.
    && chmod -R 777 /openc3/lib /openc3/gems

# Merge in the Python environment and seeded wheel cache. Ownership (root) is
# preserved from python-build.
COPY --from=python-build /openc3/python/ /openc3/python/
COPY --from=python-build /openc3/uv_cache/ /openc3/uv_cache/

# Same override as python-build, re-declared because ENV doesn't carry across
# stages. Baked into the image.
ARG PYPI_URL_OVERRIDE=
ENV PYPI_URL=${PYPI_URL_OVERRIDE:-$PYPI_URL}
ENV UV_DEFAULT_INDEX=${PYPI_URL%/}/simple

WORKDIR /openc3/

RUN mkdir /gems && chown openc3:openc3 /gems \
    && mkdir /plugins && chown openc3:openc3 /plugins \
    && chmod 777 /gems /plugins /openc3 /openc3/python

ENV HOME=/openc3
ENV XDG_CACHE_HOME=/tmp/.cache
# Runtime cache is the /gems volume, seeded from /openc3/uv_cache at startup.
# Build steps override this per RUN so wheels land in the baked seed instead.
ENV UV_CACHE_DIR=/gems/uv/
USER ${USER_ID}:${GROUP_ID}
