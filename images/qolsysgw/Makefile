BUILD_CONTEXT_DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))

APPDAEMON_VERSION ?= 4.5.13
QOLSYSGW_VERSION ?= v1.7.1
QOLSYSGW_TAG ?= tags/$(QOLSYSGW_VERSION)
QOLSYSGW_STRIP ?= qolsysgw-1.7.1

REPO := docker.io/nlowe/qolsysgw
TAG ?= $(QOLSYSGW_VERSION)-appdaemon$(APPDAEMON_VERSION)
IMAGE := $(REPO):$(TAG)

.PHONY: all
all: push

.PHONY: build
build: Dockerfile
	docker build \
		--build-arg=APPDAEMON_VERSION=$(APPDAEMON_VERSION) \
		--build-arg=QOLSYSGW_TAG=$(QOLSYSGW_TAG) \
		--build-arg=QOLSYSGW_STRIP=$(QOLSYSGW_STRIP) \
		-f Dockerfile \
		-t $(IMAGE) \
		.

.PHONY: push
push: build
	docker push $(IMAGE)
