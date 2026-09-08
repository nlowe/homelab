BUILD_CONTEXT_DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))

APPDAEMON_VERSION ?= 4.5.13
QOLSYSGW_VERSION ?= tags/v1.7.0
QOLSYSGW_STRIP ?= qolsysgw-1.7.0

REPO := docker.io/nlowe/qolsysgw
TAG ?= v$(QOLSYSGW_VERSION)-appdaemon$(APPDAEMON_VERSION)
IMAGE := $(REPO):$(TAG)

.PHONY: all
all: push

.PHONY: build
build: Dockerfile
	docker build \
		--build-arg=APPDAEMON_VERSION=$(APPDAEMON_VERSION) \
		--build-arg=QOLSYSGW_VERSION=$(QOLSYSGW_VERSION) \
		--build-arg=QOLSYSGW_STRIP=$(QOLSYSGW_STRIP) \
		-f Dockerfile \
		-t $(IMAGE) \
		.

.PHONY: push
push: build
	docker push $(IMAGE)
