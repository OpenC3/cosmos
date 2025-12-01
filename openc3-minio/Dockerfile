ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG ALPINE_VERSION=3.21
ARG GO_VERSION=1.25.4
# Also update in scripts/linux/openc3_build_ubi.sh
ARG OPENC3_MINIO_RELEASE=RELEASE.2025-10-15T17-29-55Z

FROM ${OPENC3_DEPENDENCY_REGISTRY}/golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder
ARG OPENC3_MINIO_RELEASE
COPY --chown=1001 minio-${OPENC3_MINIO_RELEASE}.tar.gz /go/minio.tar.gz
RUN tar -xzf minio.tar.gz --strip-components=1 && \
    go build

FROM ${OPENC3_DEPENDENCY_REGISTRY}/golang:${GO_VERSION}-alpine${ALPINE_VERSION}
COPY --from=builder /go/minio /usr/bin/minio
COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem
ENV IMAGE_USER=openc3
ENV IMAGE_GROUP=openc3
ENV USER_ID=1001
ENV GROUP_ID=1001

COPY --chown=1001:1001 --chmod=755 docker-entrypoint.sh /usr/bin/
RUN apk update && \
    apk upgrade && \
    rm -rf /var/cache/dnf mitigate.sh && \
    chmod +x /usr/bin/docker-entrypoint.sh && \
    addgroup -g ${GROUP_ID} -S ${IMAGE_GROUP} && \
    adduser -u ${USER_ID} -G ${IMAGE_GROUP} -s /bin/ash -S ${IMAGE_USER} && \
    mkdir /data && \
    chown -R ${USER_ID}:${IMAGE_GROUP} /data && \
    chmod -R 777 /data

# Switch to user
USER ${USER_ID}:${GROUP_ID}
EXPOSE 9000
VOLUME /data
ENTRYPOINT ["/usr/bin/docker-entrypoint.sh"]
CMD ["minio"]
