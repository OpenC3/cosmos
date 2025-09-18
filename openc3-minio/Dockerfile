ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
# Consider updating openc3_build_ubi.sh when changing the release version
# and build_multi_arch.sh
ARG OPENC3_MINIO_RELEASE=RELEASE.2025-09-07T16-13-09Z
FROM ${OPENC3_DEPENDENCY_REGISTRY}/minio/minio:${OPENC3_MINIO_RELEASE}

COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem

RUN mkdir -p /data && chown 1001:1001 /data
RUN ["chmod", "-R", "777", "/data/"]

USER 1001
