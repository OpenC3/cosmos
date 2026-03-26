ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE=openc3-base

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_IMAGE}:${OPENC3_TAG}

WORKDIR /src/
COPY Gemfile ./

USER root

ENV SKIP_DEV_GEMS=1
RUN bundle config set --local without 'development test' && \
    bundle install --quiet && \
    rm -rf /usr/lib/ruby/gems/*/cache/* /var/cache/apk/* /tmp/* /var/tmp/*

RUN ["chown", "-R", "openc3:openc3", "/src/"]
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} ./ ./
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
