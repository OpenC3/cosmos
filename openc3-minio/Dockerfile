ARG OPENC3_DEPENDENCY_REGISTRY=docker.io

FROM ${OPENC3_DEPENDENCY_REGISTRY}/minio/minio:RELEASE.2022-10-29T06-21-33Z

COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem
