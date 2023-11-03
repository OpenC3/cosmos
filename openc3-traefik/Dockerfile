ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
FROM ${OPENC3_DEPENDENCY_REGISTRY}/traefik:v2.10.4
COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem
COPY ./traefik.yaml /etc/traefik/traefik.yaml
EXPOSE 80

# We could do this but it isn't necessary and isn't portable to ubi8 images
# RUN if [[ $OPENC3_DEPENDENCY_REGISTRY == 'docker.io' ]]; then \
#   apk update && apk upgrade; \
#   fi
