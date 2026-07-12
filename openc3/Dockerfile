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

WORKDIR /openc3/python

# Install the openc3 Python package and dependencies using UV in a single sync.
# The build cache mount avoids re-downloading wheels; doing deps + project +
# smoke test in one layer avoids redundant venv layers. --chmod on the COPY and
# the trailing chmod keep the venv writable for arbitrary-UID deployments.
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} --chmod=777 python/ .

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev \
    && uv run python -Ic 'import openc3; print("openc3 imported successfully")' \
    && chmod -R 777 /openc3/python/.venv

WORKDIR /openc3/

RUN mkdir /gems && chown openc3:openc3 /gems \
    && mkdir /plugins && chown openc3:openc3 /plugins \
    && chmod 777 /gems /plugins /openc3

ENV HOME=/openc3
ENV XDG_CACHE_HOME=/tmp/.cache
ENV UV_CACHE_DIR=/gems/uv/
USER ${USER_ID}:${GROUP_ID}
