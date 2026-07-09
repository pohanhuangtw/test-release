RUNNER := docker
IMAGE_BUILDER := $(RUNNER) buildx
MACHINE := neuvector
BUILDX_ARGS =
DEFAULT_PLATFORMS := linux/amd64,linux/arm64,linux/x390s,linux/riscv64

TARGET_PLATFORMS ?= linux/amd64,linux/arm64
REPO ?= neuvector
IMAGE = $(REPO)/scanner:$(TAG)
BUILD_ACTION = --load

IMAGE_ARGS?=

buildx-machine:
	docker buildx ls
	@docker buildx ls | grep $(MACHINE) || \
	docker buildx create --name=$(MACHINE) --platform=$(DEFAULT_PLATFORMS)

test-image:
	# Instead of loading image, target all platforms, effectivelly testing
	# the build for the target architectures.
	$(MAKE) build-image BUILD_ACTION="--platform=$(TARGET_PLATFORMS)"

build-image: buildx-machine ## build (and load) the container image targeting the current platform.
	$(IMAGE_BUILDER) build -f package/Dockerfile \
		--builder $(MACHINE) $(IMAGE_ARGS) \
		--build-arg VERSION=$(VERSION) --build-arg COMMIT=$(COMMIT) -t "$(IMAGE)" $(BUILD_ACTION) .
	@echo "Built $(IMAGE)"

push-image: buildx-machine
	$(IMAGE_BUILDER) build -f package/Dockerfile \
		--builder $(MACHINE) $(IMAGE_ARGS) $(IID_FILE_FLAG) $(BUILDX_ARGS) \
		--build-arg VERSION=$(VERSION) --build-arg COMMIT=$(COMMIT) --build-arg VULNDBVER=$(VULNDBVER) --platform=$(TARGET_PLATFORMS) -t "$(REPO)/scanner.private:$(TAG)" --push .
	@echo "Pushed $(IMAGE)"
