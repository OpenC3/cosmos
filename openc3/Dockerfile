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
  && bundle config set --local without 'development' \
  && bundle install --quiet \
  && rake gems \
  && gem install --local ./openc3-*.gem \
  && openc3_gem=$(dirname `gem which openc3`) \
  && ln -s $openc3_gem/openc3 $openc3_gem/cosmos \
  && mkdir -p gems \
  && mv *.gem gems/. \
  && gem cleanup \
  && rm -rf /usr/lib/ruby/gems/*/cache/* /var/cache/apk/* /tmp/* /var/tmp/*

WORKDIR /openc3/python

RUN . /openc3/venv/bin/activate \
  && pip3 install -r requirements.txt && pip3 install --pre .

WORKDIR /openc3/

RUN mkdir /gems && chown openc3:openc3 /gems
RUN mkdir /plugins && chown openc3:openc3 /plugins
RUN ["chmod", "-R", "777", "/gems/"]
RUN ["chmod", "-R", "777", "/plugins/"]
RUN ["chmod", "-R", "777", "/openc3/"]
ENV HOME=/openc3
USER ${USER_ID}:${GROUP_ID}
