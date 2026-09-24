ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG TRAEFIK_CONFIG=traefik.yaml
# Search OPENC3_TRAEFIK_RELEASE when changing and update all as needed
ARG OPENC3_TRAEFIK_RELEASE=v3.7.13
FROM ${OPENC3_DEPENDENCY_REGISTRY}/traefik:${OPENC3_TRAEFIK_RELEASE}

# An ARG declared before a FROM is outside of a build stage, so it can’t be
# used in any instruction after a FROM. So we need to re-ARG.
ARG OPENC3_DEPENDENCY_REGISTRY
ARG TRAEFIK_CONFIG

COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem
COPY ./${TRAEFIK_CONFIG} /etc/traefik/traefik.yaml
EXPOSE 80

# ironbank hardened image includes a toml config that is favored over the yaml we copy to the image
# This default config needs to be removed for traefik to use our custom config instead
USER root
RUN rm /etc/traefik/traefik.toml || true

# Set user and group
ENV IMAGE_USER=openc3
ENV IMAGE_GROUP=openc3
ENV USER_ID=1001
ENV GROUP_ID=1001

# On docker.io (alpine) create the non-root user and upgrade with apk.
# The ironbank image already has uid 1001, but it is only rebuilt on RedHat's
# schedule, so pull the RPM security fixes released since with dnf.
RUN if [[ $OPENC3_DEPENDENCY_REGISTRY == 'docker.io' ]]; then \
  addgroup -g ${GROUP_ID} -S ${IMAGE_GROUP}; \
  adduser -u ${USER_ID} -G ${IMAGE_GROUP} -s /bin/ash -S ${IMAGE_USER}; \
  apk update && apk upgrade; \
  else \
  dnf -y upgrade && \
  dnf clean all && \
  rm -rf /var/cache/dnf; \
  fi

# Switch to user
USER ${USER_ID}
COPY --chown=1001:1001  --chmod=755 ./entrypoint.sh /entrypoint.sh