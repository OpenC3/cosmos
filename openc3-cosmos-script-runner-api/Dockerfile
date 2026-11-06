ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE=openc3-base

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_IMAGE}:${OPENC3_TAG}

# anycable-go is only run by the API images, so copy it here instead of into
# openc3-ruby. The anycable build context is provided by compose-build.yaml
# (additional_contexts) or by --build-context in the other build scripts.
# TARGETARCH is set by BuildKit and must be amd64 or arm64 to match the
# binaries in openc3-anycable/. Copied before the source so API edits don't
# invalidate this layer.
ARG TARGETARCH
COPY --from=anycable --chmod=755 anycable-go-linux-${TARGETARCH} /usr/bin/anycable-go

WORKDIR /src/

RUN ["chown", "-R", "openc3:openc3", "/src/"]

USER root

COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} ./ ./

ENV SKIP_DEV_GEMS=1
RUN bundle config set --local without 'development test' && \
    bundle install --quiet && \
    rm -rf /usr/local/lib/ruby/gems/*/cache/* /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*

RUN ["chown", "openc3:openc3", "/src/Gemfile.lock"]

# Create a /tmp directory with global write permissions including the sticky bit (chmod -R 1777)
# This is required for Ruby to be able to call Dir.mktmpdir and create temporary directories.
# The sticky bit ensures that only the owner of a file can delete it,
# even if other users have write permissions to the directory.
RUN mkdir -p /tmp && \
    rm -rf /src/tmp && \
    ln -s /tmp /src/tmp && \
    chmod -R 1777 /src/tmp && \
    chmod -R 555 /src/scripts

EXPOSE 2902

USER ${USER_ID}:${GROUP_ID}

ENV HOME=/tmp
ENV TMPDIR=/tmp
CMD [ "shoreman" ]
