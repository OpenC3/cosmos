ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE=openc3-base

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/${OPENC3_IMAGE}:${OPENC3_TAG}

WORKDIR /migration/

# Copy migration microservice code
COPY --chown=openc3:openc3 bin_file_processor.py ./
COPY --chown=openc3:openc3 migration_microservice.py ./
COPY --chown=openc3:openc3 pyproject.toml ./

USER ${USER_ID}:${GROUP_ID}

# Run the migration microservice
CMD [ "python3", "migration_microservice.py"]
