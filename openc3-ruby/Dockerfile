# Make managed in .env-build
ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG ALPINE_VERSION=3.21
ARG ALPINE_BUILD=3

# Should be loaded from ARG
FROM ${OPENC3_DEPENDENCY_REGISTRY}/alpine:${ALPINE_VERSION}.${ALPINE_BUILD}

# An ARG declared before a FROM is outside of a build stage, so it can’t be
# used in any instruction after a FROM. So we need to re-ARG ALPINE_VERSION

ARG ALPINE_VERSION
ARG APK_URL
ARG RUBYGEMS_URL
ARG PYPI_URL=https://pypi.org

ENV ALPINE_VERSION=${ALPINE_VERSION}
ENV APK_URL=${APK_URL}
ENV RUBYGEMS_URL=${RUBYGEMS_URL}
ENV PYPI_URL=${PYPI_URL}

# NOTE: This must match the alpine image used above in FROM
RUN echo "${APK_URL}/alpine/v${ALPINE_VERSION}/main" > /etc/apk/repositories \
  && echo "${APK_URL}/alpine/v${ALPINE_VERSION}/community" >> /etc/apk/repositories

LABEL maintainer="support@openc3.com"

# We require a local certificate file so set that up.
# You must place a valid cacert.pem file in your OpenC3 development folder for this work
# Comment out these lines if this is not required in your environment
COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem

ENV NOKOGIRI_USE_SYSTEM_LIBRARIES=1

COPY .gemrc /root/.gemrc
RUN sed -i "s|RUBYGEMS_URL|${RUBYGEMS_URL}|g" /root/.gemrc
RUN cp /root/.gemrc /etc/gemrc
ENV GEMRC=/etc/gemrc

COPY anycable* /usr/bin
RUN /usr/bin/anycable_install.sh

COPY shoreman.sh /usr/bin/shoreman

RUN apk update \
  && apk upgrade \
  && apk add --no-cache \
  autoconf \
  automake \
  build-base \
  ca-certificates \
  cmake \
  curl \
  git \
  htop \
  less \
  libc6-compat \
  # Ruby 3.2+ no longer bundles libffi so explicitly include
  libffi-dev \
  libtool \
  libxml2-dev \
  libxslt-dev \
  libpq-dev \
  openblas-dev \
  openssl \
  openssl-dev \
  py3-pip \
  python3 \
  python3-dev \
  rbspy \
  ruby \
  ruby-bigdecimal \
  ruby-dev \
  ruby-etc \
  ruby-io-console \
  ruby-irb \
  tini \
  # Ruby 3.2+ no longer bundles libyaml so explicitly include
  yaml-dev \
  zeromq-dev \
  && gem update --system \
  && gem install rake \
  && gem install google-protobuf \
  # This needs to be installed with the --platform flag to avoid errors on linux-musl
  # See: https://github.com/protocolbuffers/protobuf/issues/16853#issuecomment-2583135716
  # Pending merge of https://github.com/grpc/grpc/pull/39549
  # Should be fixed June 2025, look for grpc > 1.73.0 with a x86-linux-musl platform
  && gem install grpc --platform ruby \
  && gem cleanup \
  && bundle config build.nokogiri --use-system-libraries \
  && bundle config git.allow_insecure true \
  && python3 -m venv /openc3/venv \
  && source /openc3/venv/bin/activate \
  && pip3 config --global set global.index $PYPI_URL/pypi \
  && pip3 config --global set global.index-url $PYPI_URL/simple \
  && pip3 install --upgrade pip setuptools \
  && pip3 install poetry \
  && pip3 install poetry-plugin-export \
  # Note this is needed to prevent pip disappearing in some build environments
  && cp /openc3/venv/bin/pip* /openc3

# Note this is needed to fix pip files disappearing in some build environments
RUN mv /openc3/pip* /openc3/venv/bin/.

# libsocketcan - used by libcsp - https://github.com/linux-can/libsocketcan
COPY libsocketcan-0.0.12.tar.gz /opt/libsocketcan-0.0.12.tar.gz
RUN cd /opt \
  && tar -xzf libsocketcan-0.0.12.tar.gz \
  && cd libsocketcan-0.0.12 \
  && autoreconf --force --install --symlink -Wall \
  && ./configure \
  && make \
  && make install \
  && cd /opt \
  && rm -rf libsocketcan-0.0.12 \
  && rm libsocketcan-0.0.12.tar.gz

# libcsp - https://github.com/libcsp/libcsp
COPY libcsp-6b6e2dd2870bd1f8ab4516123f1fa255d6c1b632.zip /opt/libcsp-6b6e2dd2870bd1f8ab4516123f1fa255d6c1b632.zip
RUN cd /opt \
  && unzip libcsp-6b6e2dd2870bd1f8ab4516123f1fa255d6c1b632.zip \
  && cd libcsp-6b6e2dd2870bd1f8ab4516123f1fa255d6c1b632 \
  # Patches to fix compilation issues
  && sed -i '1s/^/#include <sys\/select.h>/' src/drivers/can/can_socketcan.c \
  && sed -i '2s/^/#include <endian.h>/' src/drivers/eth/eth_linux.c \
  && mkdir build \
  && cd build \
  && cmake .. -DCSP_ENABLE_PYTHON3_BINDINGS=ON -DCSP_USR_RTABLE=ON \
  && make \
  && make install \
  && cp libcsp_py3* /usr/lib/python3.12/lib-dynload/. \
  && cd /opt \
  && rm -rf libcsp-6b6e2dd2870bd1f8ab4516123f1fa255d6c1b632 \
  && rm libcsp-6b6e2dd2870bd1f8ab4516123f1fa255d6c1b632.zip

# Set user and group
ENV IMAGE_USER=openc3
ENV IMAGE_GROUP=openc3
ENV USER_ID=1001
ENV GROUP_ID=1001
# The build time venv is at /openc3/venv and the runtime venv is at /gems/python_packages
# NOTE: This is declared as PYTHONUSERBASE: "/gems/python_packages" in compose.yaml
ENV PYTHONPATH=/openc3/venv/lib/python3.12/site-packages/:/gems/python_packages/lib/python3.12/site-packages/
RUN addgroup -g ${GROUP_ID} -S ${IMAGE_GROUP}
RUN adduser -u ${USER_ID} -G ${IMAGE_GROUP} -s /bin/ash -S ${IMAGE_USER}

# Switch to user
USER ${USER_ID}:${GROUP_ID}

ENTRYPOINT [ "/sbin/tini", "--" ]
