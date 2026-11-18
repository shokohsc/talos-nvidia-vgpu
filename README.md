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
3. Builds the exact Talos 1.13.10 kernel tree from pinned `siderolabs/pkgs` commit `9b044c593c71b0ea6deb9985b7907e008b91220c` and pushes the scratch build image directly to GHCR, retaining `Module.symvers` and `/toolchain` without exporting the full tree to the ephemeral runner. The immutable image tag is reused on subsequent runs.
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

Override `TALOS_VERSION`, `NVIDIA_DRIVER_VERSION`, `KERNEL_IMAGE`, or `EXTENSION_IMAGE` when using a different pinned build. The kernel image is built and pushed directly by BuildKit to GHCR so the bldr build can consume the exact generated kernel tree. Only the small `kernel.release` metadata file is exported locally for validation; the final extension is exported as an OCI archive.

## Kernel build pins

See [docs/kernel-build.md](docs/kernel-build.md) for the source checksums, kernel config, LLVM image, and reproducible kernel build command.

## Proxmox and Talos

Configure a full-card vGPU profile on Proxmox and assign that mediated device to the Talos VM. P4-8Q and P40-24Q are candidate profiles only; confirm availability against the installed vGPU Manager, GPU SKU, and licensing. Do not install host-side `nvidia-vgpu-vfio` in Talos.

## NVIDIA device nodes on Talos

Talos system extensions cannot contain device special files. The package therefore includes the driver-matched `nvidia-modprobe` utility and a udev rule under `/usr/lib/udev/rules.d/`. When the NVIDIA kernel character device is registered, udev invokes `nvidia-modprobe` as root to create the NVIDIA control/GPU, UVM, and modeset device nodes. The helper is not installed setuid; udev already executes it with the required privileges.

This avoids relying on a display server or a Kubernetes privileged pod to create host device nodes. The extension build validates that the utility and rule are present, but runtime validation must still confirm the rule fires and the expected character devices appear after reboot.

## Validation status

CI compile and package success does not establish runtime compatibility. Before deployment, validate module vermagic, symbol versions against the exact `Module.symvers`, signature policy, module load, NVRM initialization, udev-created device nodes, vGPU enumeration, and a real workload.


## NVIDIA vGPU licensing on Talos

The extension includes a dedicated `nvidia-gridd` Talos extension service. For NVIDIA License System (FastAPI-DLS), it retrieves a fresh Linux client configuration token at service startup; the token is never stored in Talos machine configuration, Git, build artifacts, or the OCI image.

### FastAPI-DLS endpoint

The default endpoint is `https://dls.home.arpa`. The extension requests:

```text
GET https://dls.home.arpa/-/client-token
```

This is FastAPI-DLS's documented client-token endpoint. The response is written directly to `/etc/nvidia/ClientConfigToken/client_configuration_token.tok` in the service's private writable rootfs, with restrictive permissions, before `nvidia-gridd` starts.

The endpoint is configurable through the non-secret `NVIDIA_DLS_URL` environment variable in the `ExtensionServiceConfig` document. The fetcher also explicitly loads the mounted Talos CA bundle into its Go TLS root pool. The bundle path defaults to `/etc/ssl/certs/ca-certificates.crt` and can be overridden with `NVIDIA_DLS_CA_BUNDLE`:

```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: nvidia-gridd
environment:
  - NVIDIA_DLS_URL=https://dls.home.arpa
  - NVIDIA_DLS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
  - NVIDIA_DLS_INSECURE_SKIP_VERIFY=true # optional; disables certificate verification
```

You can omit this document entirely to use the default. No token is placed in this configuration.

### TLS verification bypass (opt-in)

By default, the fetcher verifies the DLS server certificate using the Talos trust bundle. To explicitly bypass certificate-chain and hostname verification, set `NVIDIA_DLS_INSECURE_SKIP_VERIFY=true` in the `ExtensionServiceConfig` environment. HTTPS encryption remains enabled and redirects to non-HTTPS URLs are still rejected, but a man-in-the-middle can impersonate the DLS server and supply a malicious token. Use only on a trusted network and remove the setting once CA trust is fixed. The bypass is disabled by default.

### Private CA trust

Without the opt-in bypass, the token fetcher uses HTTPS with normal certificate verification. The service mounts Talos' `/etc/ssl/certs` trust store read-only, so add your private CA to Talos' trusted roots. The CA certificate is public trust material, not a client token; do not put a private CA key in Talos or this repository.

The fetcher retrieves the token at every service start and fails closed if DNS, TLS validation, the endpoint, or the response fails. Talos will restart the service according to its restart policy. FastAPI-DLS client tokens are long-lived; NVIDIA's licensing client handles lease renewal after startup.

### Legacy GRID License Server

The optional legacy GRID licensing mode remains available through a `/run/gridd.conf` override. It is separate from FastAPI-DLS/NVIDIA License System and should only be used when connecting to a legacy GRID License Server.

The service's runtime logs and NVIDIA's `nvidia-smi -q` license status are the source of truth. A successful extension build or a running `nvidia-gridd` process alone does not prove that a license was acquired.

## NVIDIA containerd runtime on Talos

See [docs/containerd-nvidia-runtime.md](docs/containerd-nvidia-runtime.md) for the standalone toolkit extension, which installs the runtime and automatically registers the `nvidia` handler through Talos containerd configuration.


## NVIDIA Container Toolkit

The separate `nvidia-container-toolkit` system extension packages NVIDIA Container Toolkit 1.17.8 and `libnvidia-container` 1.17.8 without installing or replacing the GRID driver userspace. Because GRID NVML/CUDA libraries are glibc-linked while Talos is musl-based, the Toolkit payload is built against glibc and carries a private glibc loader/runtime under `/usr/local/lib`; it does not replace Talos' libc. Build it with `make toolkit-build`. It provides the `nvidia-container-runtime`, CLI, hooks, and the named containerd runtime handler. See [docs/containerd-nvidia-runtime.md](docs/containerd-nvidia-runtime.md). Install it alongside `nvidia-vgpu-guest` in the Talos Image Factory schematic. The Kubernetes RuntimeClass and NVIDIA device plugin remain separate cluster resources.
