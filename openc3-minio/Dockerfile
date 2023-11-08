ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
FROM ${OPENC3_DEPENDENCY_REGISTRY}/minio/minio:RELEASE.2023-10-07T15-07-38Z

# An ARG declared before a FROM is outside of a build stage, so it can’t be
# used in any instruction after a FROM. So we need to re-ARG OPENC3_DEPENDENCY_REGISTRY
ARG OPENC3_DEPENDENCY_REGISTRY

COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem

# Update packages to eliminate CVEs if we're on docker.io (not ironbank)
RUN if [[ $OPENC3_DEPENDENCY_REGISTRY == 'docker.io' ]]; then \
  microdnf update --nodocs -y && microdnf clean all; \
  fi
