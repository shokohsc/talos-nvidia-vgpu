.PHONY: validate-artifacts push-artifacts build local clean

ARTIFACT_IMAGE ?=
TALOS_VERSION ?=
KERNEL_RELEASE ?=
EXTENSION_IMAGE ?=
PLATFORM ?= linux/amd64

require-%:
	@test -n "$($*)" || (echo "ERROR: $* is required" >&2; exit 2)

validate-artifacts: require-KERNEL_RELEASE
	KERNEL_RELEASE="$(KERNEL_RELEASE)" ./scripts/validate-artifacts.sh dist/rootfs

push-artifacts: require-ARTIFACT_IMAGE
	docker buildx build --platform "$(PLATFORM)" -f Dockerfile.artifacts -t "$(ARTIFACT_IMAGE)" --push .

build: require-ARTIFACT_IMAGE require-TALOS_VERSION require-KERNEL_RELEASE require-EXTENSION_IMAGE
	KERNEL_RELEASE="$(KERNEL_RELEASE)" ./scripts/validate-artifacts.sh dist/rootfs
	docker buildx build --platform "$(PLATFORM)" -f Pkgfile --target nvidia-vgpu-guest --build-arg ARTIFACT_IMAGE="$(ARTIFACT_IMAGE)" --build-arg TALOS_VERSION="$(TALOS_VERSION)" --build-arg KERNEL_RELEASE="$(KERNEL_RELEASE)" -t "$(EXTENSION_IMAGE)" --push .

local: require-ARTIFACT_IMAGE require-TALOS_VERSION require-KERNEL_RELEASE
	KERNEL_RELEASE="$(KERNEL_RELEASE)" ./scripts/validate-artifacts.sh dist/rootfs
	docker buildx build --platform "$(PLATFORM)" -f Pkgfile --target nvidia-vgpu-guest --build-arg ARTIFACT_IMAGE="$(ARTIFACT_IMAGE)" --build-arg TALOS_VERSION="$(TALOS_VERSION)" --build-arg KERNEL_RELEASE="$(KERNEL_RELEASE)" --output type=local,dest=_out .

clean:
	rm -rf _out