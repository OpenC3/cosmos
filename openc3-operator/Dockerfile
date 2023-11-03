ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_TAG=latest
ARG OPENC3_IMAGE=openc3-base

FROM ${OPENC3_REGISTRY}/openc3inc/${OPENC3_IMAGE}:${OPENC3_TAG}

WORKDIR /openc3/lib/openc3/operators/

USER ${USER_ID}:${GROUP_ID}

CMD [ "ruby", "microservice_operator.rb"]
