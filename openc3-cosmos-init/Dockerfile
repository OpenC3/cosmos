ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_NODE_IMAGE=openc3-node
ARG OPENC3_BASE_IMAGE=openc3-base
# Update in openc3_build_ubi.sh when changing the release version
# and build_multi_arch.sh
ARG OPENC3_MC_RELEASE=RELEASE.2025-08-13T08-35-41Z

FROM ${OPENC3_DEPENDENCY_REGISTRY}/minio/mc:${OPENC3_MC_RELEASE} AS minio-mc
# Setup our node build image
FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_NODE_IMAGE}:${OPENC3_TAG} AS openc3-frontend-tmp

# Set work dir to start building the plugins
WORKDIR /openc3/plugins/
USER root

# Copy in all the package.json files so we can pnpm install everything
COPY ./plugins/*.json ./
COPY ./plugins/*.yaml ./
COPY ./plugins/packages/openc3-tool-base/*.json packages/openc3-tool-base/
COPY ./plugins/packages/openc3-cosmos-tool-admin/*.json packages/openc3-cosmos-tool-admin/
COPY ./plugins/packages/openc3-cosmos-tool-bucketexplorer/*.json packages/openc3-cosmos-tool-bucketexplorer/
COPY ./plugins/packages/openc3-cosmos-tool-cmdsender/*.json packages/openc3-cosmos-tool-cmdsender/
COPY ./plugins/packages/openc3-cosmos-tool-cmdtlmserver/*.json packages/openc3-cosmos-tool-cmdtlmserver/
COPY ./plugins/packages/openc3-cosmos-tool-dataextractor/*.json packages/openc3-cosmos-tool-dataextractor/
COPY ./plugins/packages/openc3-cosmos-tool-dataviewer/*.json packages/openc3-cosmos-tool-dataviewer/
COPY ./plugins/packages/openc3-cosmos-tool-iframe/*.json packages/openc3-cosmos-tool-iframe/
COPY ./plugins/packages/openc3-cosmos-tool-handbooks/*.json packages/openc3-cosmos-tool-handbooks/
COPY ./plugins/packages/openc3-cosmos-tool-limitsmonitor/*.json packages/openc3-cosmos-tool-limitsmonitor/
COPY ./plugins/packages/openc3-cosmos-tool-packetviewer/*.json packages/openc3-cosmos-tool-packetviewer/
COPY ./plugins/packages/openc3-cosmos-tool-scriptrunner/*.json packages/openc3-cosmos-tool-scriptrunner/
COPY ./plugins/packages/openc3-cosmos-tool-tablemanager/*.json packages/openc3-cosmos-tool-tablemanager/
COPY ./plugins/packages/openc3-cosmos-tool-tlmgrapher/*.json packages/openc3-cosmos-tool-tlmgrapher/
COPY ./plugins/packages/openc3-cosmos-tool-tlmviewer/*.json packages/openc3-cosmos-tool-tlmviewer/
COPY ./plugins/packages/openc3-js-common/ packages/openc3-js-common/
COPY ./plugins/packages/openc3-vue-common/ packages/openc3-vue-common/
COPY ./plugins/packages/openc3-cosmos-demo/*.json packages/openc3-cosmos-demo/

ARG NPM_URL=https://registry.npmjs.org
RUN pnpm config set registry ${NPM_URL}
RUN pnpm config set fetch-timeout 600000
RUN pnpm install --frozen-lockfile --ignore-scripts

# Build @openc3/js-common and @openc3/vue-common
RUN pnpm build:common

# Copy in helper scripts for building
COPY ./plugins/docker-package-build.sh ./plugins/eslint.config.mjs ./plugins/.nycrc ./
RUN chmod +x ./docker-package-build.sh

FROM openc3-frontend-tmp AS openc3-tmp1
COPY ./plugins/packages/openc3-tool-base/ packages/openc3-tool-base/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-tool-base"]

# Build admin tool
COPY ./plugins/packages/openc3-cosmos-tool-admin/ packages/openc3-cosmos-tool-admin/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-admin"]

# Build bucketexplorer tool
COPY ./plugins/packages/openc3-cosmos-tool-bucketexplorer/ packages/openc3-cosmos-tool-bucketexplorer/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-bucketexplorer"]

# Build cmdsender tool
COPY ./plugins/packages/openc3-cosmos-tool-cmdsender/ packages/openc3-cosmos-tool-cmdsender/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-cmdsender"]

# Build cmdtlmserver tool
FROM openc3-frontend-tmp AS openc3-tmp2
COPY ./plugins/packages/openc3-cosmos-tool-cmdtlmserver/ packages/openc3-cosmos-tool-cmdtlmserver/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-cmdtlmserver"]

# Build tablemanager tool
COPY ./plugins/packages/openc3-cosmos-tool-tablemanager/ packages/openc3-cosmos-tool-tablemanager/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-tablemanager"]

# Build dataextractor tool
COPY ./plugins/packages/openc3-cosmos-tool-dataextractor/ packages/openc3-cosmos-tool-dataextractor/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-dataextractor"]

# Build dataviewer tool
COPY ./plugins/packages/openc3-cosmos-tool-dataviewer/ packages/openc3-cosmos-tool-dataviewer/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-dataviewer"]

# Build iframe tool
FROM openc3-frontend-tmp AS openc3-tmp3
COPY ./plugins/packages/openc3-cosmos-tool-iframe/ packages/openc3-cosmos-tool-iframe/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-iframe"]

# Build handbooks tool
COPY ./plugins/packages/openc3-cosmos-tool-handbooks/ packages/openc3-cosmos-tool-handbooks/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-handbooks"]

# Build limitsmonitor tool
COPY ./plugins/packages/openc3-cosmos-tool-limitsmonitor/ packages/openc3-cosmos-tool-limitsmonitor/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-limitsmonitor"]

# Build packetviewer tool
COPY ./plugins/packages/openc3-cosmos-tool-packetviewer/ packages/openc3-cosmos-tool-packetviewer/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-packetviewer"]

# Build tlmgrapher tool
FROM openc3-frontend-tmp AS openc3-tmp4
COPY ./plugins/packages/openc3-cosmos-tool-tlmgrapher/ packages/openc3-cosmos-tool-tlmgrapher/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-tlmgrapher"]

# Build tlmviewer tool
COPY ./plugins/packages/openc3-cosmos-tool-tlmviewer/ packages/openc3-cosmos-tool-tlmviewer
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-tlmviewer"]

# Build scriptrunner tool
COPY ./plugins/packages/openc3-cosmos-tool-scriptrunner/ packages/openc3-cosmos-tool-scriptrunner/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-scriptrunner"]

# Build demo config
COPY ./plugins/packages/openc3-cosmos-demo/ packages/openc3-cosmos-demo/
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-demo"]

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_BASE_IMAGE}:${OPENC3_TAG} AS base
FROM openc3-frontend-tmp AS openc3-tmp5

# Build docs tool
COPY --from=base /openc3 /openc3/
COPY --from=docs . /openc3/openc3-cosmos-tool-docs/
WORKDIR /openc3/openc3-cosmos-tool-docs/scripts
RUN ruby generate_docs_from_yaml.rb PLUGIN
WORKDIR /openc3/openc3-cosmos-tool-docs
RUN pnpm install --frozen-lockfile --ignore-scripts
RUN ["/openc3/plugins/docker-package-build.sh", "openc3-cosmos-tool-docs", "/openc3/openc3-cosmos-tool-docs"]

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_BASE_IMAGE}:${OPENC3_TAG}

# Switch back to openc3 user for copies
USER ${USER_ID}:${GROUP_ID}
# Copy in gems, pnpm lock files, and common code
COPY --from=openc3-tmp1 --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/gems/* /openc3/plugins/gems/
COPY --from=openc3-tmp2 --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/gems/* /openc3/plugins/gems/
COPY --from=openc3-tmp3 --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/gems/* /openc3/plugins/gems/
COPY --from=openc3-tmp4 --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/gems/* /openc3/plugins/gems/
COPY --from=openc3-tmp5 --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/gems/* /openc3/plugins/gems/
COPY --from=openc3-tmp5 --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/openc3-cosmos-tool-docs/pnpm-lock.yaml /openc3/openc3-cosmos-tool-docs/pnpm-lock.yaml
COPY --from=openc3-frontend-tmp --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/packages/openc3-js-common/ /openc3/plugins/packages/openc3-js-common/
COPY --from=openc3-frontend-tmp --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/packages/openc3-vue-common/ /openc3/plugins/packages/openc3-vue-common/
COPY --from=openc3-frontend-tmp --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/pnpm-lock.yaml /openc3/plugins/pnpm-lock.yaml
COPY --from=openc3-frontend-tmp --chown=${IMAGE_USER}:${IMAGE_GROUP} /openc3/plugins/pnpm-workspace.yaml /openc3/plugins/pnpm-workspace.yaml
# Copy in other necessary code/config for the container
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} ./init.sh /openc3/
COPY --from=minio-mc --chown=${IMAGE_USER}:${IMAGE_GROUP} /bin/mc /bin/mc
COPY --chown=${IMAGE_USER}:${IMAGE_GROUP} ./script-runner.json /openc3/minio/script-runner.json

CMD [ "/openc3/init.sh" ]
