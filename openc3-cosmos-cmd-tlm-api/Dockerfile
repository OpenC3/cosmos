ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE=openc3-base

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_IMAGE}:${OPENC3_TAG}

WORKDIR /src/
COPY Gemfile Gemfile.lock* ./

USER root

ENV SKIP_DEV_GEMS=1
RUN bundle config set --local without 'development test' \
  && bundle install --quiet \
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
