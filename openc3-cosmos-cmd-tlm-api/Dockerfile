ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE=openc3-base

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_IMAGE}:${OPENC3_TAG}

WORKDIR /src/
COPY Gemfile ./

USER root

RUN bundle config set --local without 'development test' \
  && bundle install --quiet \
  # grpc needs to be uninstalled with the --platform flag to avoid errors on linux-musl
  # See: https://github.com/protocolbuffers/protobuf/issues/16853#issuecomment-2583135716
  # Should be fixed June 2025, look for grpc > 1.72.0 with a x86-linux-musl platform
  && gem uninstall grpc --platform aarch64-linux --all --force \
  && rm Gemfile.lock \
  && rm -rf /usr/lib/ruby/gems/*/cache/* \
  /var/cache/apk/* \
  /tmp/* \
  /var/tmp/*

RUN ["chown", "-R", "openc3:openc3", "/src/"]
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} ./ ./
RUN ["chmod", "-R", "777", "/src/"]

EXPOSE 2901

USER ${USER_ID}:${GROUP_ID}
CMD [ "shoreman" ]
