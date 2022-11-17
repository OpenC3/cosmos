ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_TAG=latest

FROM ${OPENC3_DEPENDENCY_REGISTRY}/minio/mc:RELEASE.2022-10-29T10-09-23Z AS minio-mc
FROM ${OPENC3_REGISTRY}/openc3inc/openc3-node:${OPENC3_TAG} AS openc3-frontend-tmp

WORKDIR /openc3/plugins/

USER root

COPY ./plugins/*.json ./
COPY ./plugins/openc3-tool-base/*.json openc3-tool-base/
COPY ./plugins/packages/openc3-cosmos-tool-admin/*.json packages/openc3-cosmos-tool-admin/
COPY ./plugins/packages/openc3-cosmos-tool-autonomic/*.json packages/openc3-cosmos-tool-autonomic/
COPY ./plugins/packages/openc3-cosmos-tool-calendar/*.json packages/openc3-cosmos-tool-calendar/
COPY ./plugins/packages/openc3-cosmos-tool-cmdsender/*.json packages/openc3-cosmos-tool-cmdsender/
COPY ./plugins/packages/openc3-cosmos-tool-cmdtlmserver/*.json packages/openc3-cosmos-tool-cmdtlmserver/
COPY ./plugins/packages/openc3-cosmos-tool-dataextractor/*.json packages/openc3-cosmos-tool-dataextractor/
COPY ./plugins/packages/openc3-cosmos-tool-dataviewer/*.json packages/openc3-cosmos-tool-dataviewer/
COPY ./plugins/packages/openc3-cosmos-tool-handbooks/*.json packages/openc3-cosmos-tool-handbooks/
COPY ./plugins/packages/openc3-cosmos-tool-limitsmonitor/*.json packages/openc3-cosmos-tool-limitsmonitor/
COPY ./plugins/packages/openc3-cosmos-tool-packetviewer/*.json packages/openc3-cosmos-tool-packetviewer/
COPY ./plugins/packages/openc3-cosmos-tool-scriptrunner/*.json packages/openc3-cosmos-tool-scriptrunner/
COPY ./plugins/packages/openc3-cosmos-tool-tablemanager/*.json packages/openc3-cosmos-tool-tablemanager/
COPY ./plugins/packages/openc3-cosmos-tool-tlmgrapher/*.json packages/openc3-cosmos-tool-tlmgrapher/
COPY ./plugins/packages/openc3-cosmos-tool-tlmviewer/*.json packages/openc3-cosmos-tool-tlmviewer/
COPY ./plugins/packages/openc3-tool-common/ packages/openc3-tool-common/
COPY ./plugins/packages/openc3-cosmos-demo/*.json packages/openc3-cosmos-demo/

ARG NPM_URL
RUN yarn config set registry $NPM_URL && yarn --network-timeout 600000

COPY ./plugins/docker-package-build.sh ./plugins/docker-package-install.sh ./plugins/babel.config.js ./plugins/.eslintrc.js ./plugins/.nycrc ./
RUN chmod +x ./docker-package-build.sh ./docker-package-install.sh
COPY ./plugins/openc3-tool-base/ openc3-tool-base/
RUN ["/openc3/plugins/docker-package-install.sh", "openc3-tool-base"]

# Build admin tool
FROM openc3-frontend-tmp AS openc3-tmp1
COPY ./plugins/packages/openc3-cosmos-tool-admin/ packages/openc3-cosmos-tool-admin/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-admin"]

# Build cmdsender tool
COPY ./plugins/packages/openc3-cosmos-tool-cmdsender/ packages/openc3-cosmos-tool-cmdsender/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-cmdsender"]

# Build cmdtlmserver tool
COPY ./plugins/packages/openc3-cosmos-tool-cmdtlmserver/ packages/openc3-cosmos-tool-cmdtlmserver/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-cmdtlmserver"]

# Build dataextractor tool
FROM openc3-frontend-tmp AS openc3-tmp2
COPY ./plugins/packages/openc3-cosmos-tool-dataextractor/ packages/openc3-cosmos-tool-dataextractor/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-dataextractor"]

# Build dataviewer tool
COPY ./plugins/packages/openc3-cosmos-tool-dataviewer/ packages/openc3-cosmos-tool-dataviewer/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-dataviewer"]

# Build handbooks tool
COPY ./plugins/packages/openc3-cosmos-tool-handbooks/ packages/openc3-cosmos-tool-handbooks/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-handbooks"]

# Build limitsmonitor tool
COPY ./plugins/packages/openc3-cosmos-tool-limitsmonitor/ packages/openc3-cosmos-tool-limitsmonitor/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-limitsmonitor"]

# Build packetviewer tool
FROM openc3-frontend-tmp AS openc3-tmp3
COPY ./plugins/packages/openc3-cosmos-tool-packetviewer/ packages/openc3-cosmos-tool-packetviewer/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-packetviewer"]

# Build scriptrunner tool
COPY ./plugins/packages/openc3-cosmos-tool-scriptrunner/ packages/openc3-cosmos-tool-scriptrunner/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-scriptrunner"]

# Build calendar tool
COPY ./plugins/packages/openc3-cosmos-tool-calendar/ packages/openc3-cosmos-tool-calendar/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-calendar"]

# Build tablemanager tool
COPY ./plugins/packages/openc3-cosmos-tool-tablemanager/ packages/openc3-cosmos-tool-tablemanager/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-tablemanager"]

# Build tlmgrapher tool
FROM openc3-frontend-tmp AS openc3-tmp4
COPY ./plugins/packages/openc3-cosmos-tool-tlmgrapher/ packages/openc3-cosmos-tool-tlmgrapher/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-tlmgrapher"]

# Build tlmviewer tool
COPY ./plugins/packages/openc3-cosmos-tool-tlmviewer/ packages/openc3-cosmos-tool-tlmviewer
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-tlmviewer"]

# Build autonomic tool
COPY ./plugins/packages/openc3-cosmos-tool-autonomic/ packages/openc3-cosmos-tool-autonomic/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-autonomic"]

# Build demo config
COPY ./plugins/packages/openc3-cosmos-demo/ packages/openc3-cosmos-demo/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-demo"]

FROM openc3-frontend-tmp AS openc3-frontend-base-tmp

COPY --from=openc3-tmp1 /openc3/plugins/gems/* /openc3/plugins/gems/
COPY --from=openc3-tmp2 /openc3/plugins/gems/* /openc3/plugins/gems/
COPY --from=openc3-tmp3 /openc3/plugins/gems/* /openc3/plugins/gems/
COPY --from=openc3-tmp4 /openc3/plugins/gems/* /openc3/plugins/gems/

FROM ${OPENC3_REGISTRY}/openc3inc/openc3-base:${OPENC3_TAG}

COPY --from=openc3-frontend-base-tmp --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/gems/* /openc3/plugins/gems/
COPY --from=openc3-frontend-base-tmp --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/packages/openc3-tool-common/ /openc3/plugins/packages/openc3-tool-common/
COPY --from=openc3-frontend-base-tmp --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/yarn.lock /openc3/plugins/yarn.lock
COPY --from=openc3-frontend-base-tmp --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/openc3-tool-base/yarn.lock /openc3/plugins/yarn-tool-base.lock
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} ./init.sh /openc3/

COPY --from=minio-mc /bin/mc /bin/mc
COPY ./script-runner.json /openc3/minio/script-runner.json

CMD [ "/openc3/init.sh" ]
