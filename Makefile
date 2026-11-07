PLATFORM ?= linux/amd64
TALOS_VERSION ?= v1.13.10
NVIDIA_DRIVER_VERSION ?= 535.161.07
NVIDIA_DRIVER_IMAGE ?= docker.io/shokohsc/nvidia-vgpu-driver:535.161.07-grid
PKGS_REF ?= 9b044c593c71b0ea6deb9985b7907e008b91220c
PKGS_DIR ?= _out/pkgs
KERNEL_BUILD_DIR ?= _out/kernel-build
KERNEL_IMAGE ?= ghcr.io/shokohsc/talos-nvidia-vgpu-kernel-build:v1.13.10
EXTENSION_IMAGE ?= _out/nvidia-vgpu-$(NVIDIA_DRIVER_VERSION)-talos-$(TALOS_VERSION).oci.tar

.PHONY: extract-driver kernel-build build local clean

require-%:
	@test -n "$($*)" || (echo "ERROR: $* is required" >&2; exit 2)

extract-driver:
	NVIDIA_DRIVER_IMAGE="$(NVIDIA_DRIVER_IMAGE)" \
	NVIDIA_DRIVER_VERSION="$(NVIDIA_DRIVER_VERSION)" \
	DRIVER_SOURCE_DIR=nvidia-vgpu-guest/driver \
	bash scripts/extract-driver.sh

kernel-build:
	@if [ ! -d "$(PKGS_DIR)/.git" ]; then \
		mkdir -p "$$(dirname "$(PKGS_DIR)")"; \
		git clone https://github.com/siderolabs/pkgs.git "$(PKGS_DIR)"; \
	fi
	git -C "$(PKGS_DIR)" checkout "$(PKGS_REF)"
	make -C "$(PKGS_DIR)" local-kernel-build PLATFORM="$(PLATFORM)" DEST="$(CURDIR)/$(KERNEL_BUILD_DIR)"
	docker buildx build --platform "$(PLATFORM)" -f "$(CURDIR)/Dockerfile.kernel-build" \
		-t "$(KERNEL_IMAGE)" --push "$(KERNEL_BUILD_DIR)"

build: require-KERNEL_IMAGE
	@mkdir -p "$(dirname "$(EXTENSION_IMAGE)")"
	@test -s nvidia-vgpu-guest/driver/kernel/Makefile || (echo "Run 'make extract-driver' first" >&2; exit 2)
	docker buildx build --platform "$(PLATFORM)" -f Pkgfile \
		--target nvidia-vgpu-guest \
		--build-arg TALOS_VERSION="$(TALOS_VERSION)" \
		--build-arg NVIDIA_DRIVER_VERSION="$(NVIDIA_DRIVER_VERSION)" \
		--build-arg KERNEL_IMAGE="$(KERNEL_IMAGE)" \
		--output "type=oci,dest=$(EXTENSION_IMAGE)" .

local: build

clean:
	rm -rf _out _work nvidia-vgpu-guest/driver
