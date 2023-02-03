ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_TAG=latest

FROM ${OPENC3_REGISTRY}/openc3inc/openc3-base:${OPENC3_TAG}

WORKDIR /src/
COPY Gemfile ./

USER root

RUN bundle config set --local without 'development'\
   && bundle install --quiet \
   && rm -rf /usr/lib/ruby/gems/*/cache/* \
     /var/cache/apk/* \
     /tmp/* \
     /var/tmp/*

RUN ["chown", "-R", "openc3:openc3", "/src/"]
COPY  --chown=${IMAGE_USER}:${IMAGE_GROUP} ./ ./
RUN ["chmod", "-R", "777", "/src/"]

EXPOSE 2902

USER ${USER_ID}:${GROUP_ID}
CMD [ "rails", "s", "-b", "0.0.0.0", "-p", "2902" ]
