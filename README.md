# talos-nvidia-vgpu

Talos Linux system extension packaging the NVIDIA vGPU guest driver for Tesla vGPU guests.

Initial target: Talos **v1.13.10 amd64**, Linux **6.18.48**, NVIDIA GRID guest driver **535.161.07**. The build is pinned to the corresponding `siderolabs/pkgs` commit. Build a distinct extension for each exact Talos kernel ABI.

> **Compatibility warning:** NVIDIA 535.161.07 predates Linux 6.18. A successful compile is not proof of runtime compatibility. Validate module loading, NVRM initialization, vGPU enumeration, and a real workload on the exact Talos VM.

## Scope

- Guest-side proprietary modules only; Proxmox retains the vGPU Manager and host-side `nvidia-vgpu-vfio`.
- Matching userspace is installed from the same GRID guest package.
- vGPU profile selection is configured on Proxmox and does not change the Talos extension build.

## CI build

The workflow consumes `docker.io/shokohsc/nvidia-vgpu-driver:535.161.07-grid` and:

1. Extracts the exact `NVIDIA-Linux-x86_64-535.161.07-grid.run` installer from the image.
2. Checks and extracts the installer on the ephemeral runner. The extracted proprietary payload is ignored by Git and is not uploaded separately.
3. Builds the exact Talos 1.13.10 kernel tree from pinned `siderolabs/pkgs` commit `9b044c593c71b0ea6deb9985b7907e008b91220c`, retaining `Module.symvers` and `/toolchain`.
4. Builds the proprietary NVIDIA guest kernel modules against that kernel tree using the matching LLVM tools.
5. Installs matching NVIDIA userspace, including `nvidia-modprobe`, into the extension rootfs. A Talos udev rule invokes the helper when the NVIDIA character device is registered, creating the `/dev/nvidia*` and UVM device nodes without shipping special files in the extension image.
6. Validates the expected modules, NVML, `nvidia-smi`, `nvidia-modprobe`, the udev rule, and the Talos extension manifest.
7. Exports an OCI image as a GitHub Actions artifact named `nvidia-vgpu-535.161.07-talos-v1.13.10` (14-day retention).

The build does not push the proprietary extension to a public container registry.

## Local extraction

With Docker installed:

```sh
DRIVER_SOURCE_DIR=nvidia-vgpu-guest/driver bash scripts/extract-driver.sh
```

## Local build

With Docker Buildx and GHCR write access:

```sh
make extract-driver
docker login ghcr.io
make kernel-build
make build
```

Override `TALOS_VERSION`, `NVIDIA_DRIVER_VERSION`, `KERNEL_IMAGE`, or `EXTENSION_IMAGE` when using a different pinned build. The kernel image is pushed to GHCR so the bldr build can consume the exact generated kernel tree; the final extension is exported locally as an OCI archive.

## Kernel build pins

See [docs/kernel-build.md](docs/kernel-build.md) for the source checksums, kernel config, LLVM image, and reproducible kernel build command.

## Proxmox and Talos

Configure a full-card vGPU profile on Proxmox and assign that mediated device to the Talos VM. P4-8Q and P40-24Q are candidate profiles only; confirm availability against the installed vGPU Manager, GPU SKU, and licensing. Do not install host-side `nvidia-vgpu-vfio` in Talos.

## NVIDIA device nodes on Talos

Talos system extensions cannot contain device special files. The package therefore includes the driver-matched `nvidia-modprobe` utility and a udev rule under `/usr/lib/udev/rules.d/`. When the NVIDIA kernel character device is registered, udev invokes `nvidia-modprobe` as root to create the NVIDIA control/GPU, UVM, and modeset device nodes. The helper is not installed setuid; udev already executes it with the required privileges.

This avoids relying on a display server or a Kubernetes privileged pod to create host device nodes. The extension build validates that the utility and rule are present, but runtime validation must still confirm the rule fires and the expected character devices appear after reboot.

## Validation status

CI compile and package success does not establish runtime compatibility. Before deployment, validate module vermagic, symbol versions against the exact `Module.symvers`, signature policy, module load, NVRM initialization, udev-created device nodes, vGPU enumeration, and a real workload.
