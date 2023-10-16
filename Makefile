.DEFAULT_GOAL := help

.PHONY:

SHELL=bash

export CONTAINER_BIN          =docker
export DOCKER_COMPOSE_COMMAND ="docker compose"

export OPENC3_USER_ID  =$(shell id -u)
export OPENC3_GROUP_ID =$(shell id -g)

export OPENC3_SCRIPT      =./openc3.sh

cli: ## run a cli command as the default user ('cli help' for more info)
	$(OPENC3_SCRIPT) cli

cliroot: ## run a cli command as the root user ('cli help' for more info)
	$(OPENC3_SCRIPT) cliroot

cli-help: ## cli help' for more info
	$(OPENC3_SCRIPT) cli help

start: ## start the docker compose openc3
	$(OPENC3_SCRIPT) start

stop: ## stop the running dockers for openc3
	$(OPENC3_SCRIPT) stop

cleanup: ## cleanup network and volumes for openc3
	$(OPENC3_SCRIPT) cleanup

build: ## build the containers for openc3
	$(OPENC3_SCRIPT) build

run: build ## run the prebuilt containers for openc3
	$(OPENC3_SCRIPT) run

dev: ## run openc3 in a dev mode
	$(OPENC3_SCRIPT) dev

test: ## test openc3
	$(OPENC3_SCRIPT) test

util: ## various helper commands
	$(OPENC3_SCRIPT) util

define print-help
$(call print-target-header,"Makefile Help")
	echo
	printf "%s" "How to use this Makefile, e.g.: make cli"
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