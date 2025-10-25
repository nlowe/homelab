BUILD_CONTEXT_DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))/addon/zone-editor

VERSION = $(shell cd $(BUILD_CONTEXT_DIR) && git rev-parse HEAD)

REPO := docker.io/nlowe/sensy-one-zone-editor
TAG := main-$(VERSION)
IMAGE := $(REPO):$(TAG)

SRCS := $(wildcard addon/zone-editor/**/*)

.PHONY: all
all: push

.PHONY: build
build: $(SRCS)
	docker build \
		-f $(BUILD_CONTEXT_DIR)/Dockerfile \
		-t $(IMAGE) \
		$(BUILD_CONTEXT_DIR)

.PHONY: push
push: build
	docker push $(IMAGE)