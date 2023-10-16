.DEFAULT_GOAL := help

.PHONY:

SHELL=bash

CONTAINER_BIN=docker

export OPENC3_USER_ID  =$(shell id -u)
export OPENC3_GROUP_ID =$(shell id -g)

cli: ## cli
	# # Source the .env file to setup environment variables
    # set -a
    # . "$(dirname -- "$0")/.env"
    # # Start (and remove when done --rm) the openc3-operator container with the current working directory
    # # mapped as volume (-v) /openc3/local and container working directory (-w) also set to /openc3/local.
    # # This allows tools running in the container to have a consistent path to the current working directory.
    # # Run the command "ruby /openc3/bin/openc3cli" with all parameters starting at 2 since the first is 'openc3'
    # args=`echo $@ | { read _ args; echo $args; }`
    # # Make sure the network exists
    # (docker network create openc3-cosmos-network || true) &> /dev/null
    # docker run -it --rm --env-file "$(dirname -- "$0")/.env" --user=$OPENC3_USER_ID:$OPENC3_GROUP_ID --network openc3-cosmos-network -v `pwd`:/openc3/local:z -w /openc3/local $OPENC3_REGISTRY/openc3inc/openc3-operator:$OPENC3_TAG ruby /openc3/bin/openc3cli $args
    # set +a
    # ;;

cliroot: ## cliroot

start: ## start

stop: ## stop

cleanup: ## cleanup

build: ## build

run: ## run

dev: ## dev

test: ## test

util: ## util

print-%: ## print a variable and its value, e.g. print the value of variable PROVIDER: make print-PROVIDER
	@echo $* = $($*)

define print-help
$(call print-target-header,"Makefile Help")
	echo
	printf "%s" "How to use this Makefile"
	echo
$(call print-target-header,"target                         description")
	grep -E '^([a-zA-Z_-]).+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS=":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' | grep $(or $1,".*")
	echo
endef

help:
	@$(call print-help)

help-%: ## Filtered help, e.g.: make help-OPENC3_USER_ID
	@$(call print-help,$*)

print-%: ## print variable and its value, e.g.: make print-OPENC3_USER_ID
	@echo $*=$($*)