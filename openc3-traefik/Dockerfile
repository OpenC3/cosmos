ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG TRAEFIK_CONFIG=traefik.yaml
# NOTE: 2.11.2 is the last valid 2.11 version on IronBank
FROM ${OPENC3_DEPENDENCY_REGISTRY}/traefik:v2.11.2

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

# Create non-root user and update packages if we're on docker.io (not ironbank)
RUN if [[ $OPENC3_DEPENDENCY_REGISTRY == 'docker.io' ]]; then \
  addgroup -g ${GROUP_ID} -S ${IMAGE_GROUP}; \
  adduser -u ${USER_ID} -G ${IMAGE_GROUP} -s /bin/ash -S ${IMAGE_USER}; \
  apk update && apk upgrade; \
  fi

# Switch to user
USER ${USER_ID}
COPY --chown=1001:1001  --chmod=755 ./entrypoint.sh /entrypoint.sh