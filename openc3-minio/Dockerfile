ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
FROM ${OPENC3_DEPENDENCY_REGISTRY}/minio/minio:RELEASE.2024-01-05T22-17-24Z

# An ARG declared before a FROM is outside of a build stage, so it can’t be
# used in any instruction after a FROM. So we need to re-ARG OPENC3_DEPENDENCY_REGISTRY
ARG OPENC3_DEPENDENCY_REGISTRY

COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem

RUN mkdir -p /data && chown 1001:1001 /data
RUN ["chmod", "-R", "777", "/data/"]

USER 1001
