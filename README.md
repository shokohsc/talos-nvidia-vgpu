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

The extension includes a dedicated `nvidia-gridd` Talos extension service. It starts after networking, the NVIDIA device nodes, and its `ExtensionServiceConfig` are available. The service runs in its own container rootfs and receives the host NVIDIA devices, procfs/sysfs, and Talos CA trust bundle.

### NVIDIA License System (DLS/CLS)

For NVIDIA License System, generate a Linux client configuration token (`.tok`) from the license service. The token contains the service-instance information, including the endpoint; do not set the HTTPS FQDN as `ServerAddress` in `gridd.conf`. NVIDIA's Linux client uses `FeatureType=1` for vGPU and reads the token from `/etc/nvidia/ClientConfigToken/`.

Add an `ExtensionServiceConfig` document to the Talos machine configuration. Keep the token out of Git and out of the extension image; inject it from your secret-management workflow:

```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: nvidia-gridd
configFiles:
  - mountPath: /run/nvidia-client-token.tok
    content: |
      <paste the complete client configuration token here>
```

The service copies the mounted token into its private writable rootfs and sets mode `0744` before starting `nvidia-gridd`. The token is not baked into the OCI image. The HTTPS endpoint's certificate must chain to a CA trusted by Talos; add your private CA to the Talos trusted roots so it is present under `/etc/ssl/certs`.

Apply the multi-document configuration using your normal Talos configuration workflow, for example:

```sh
talosctl apply-config --nodes <talos-node> --file <complete-machine-config.yaml>
```

Because this is an `ExtensionServiceConfig` document, retain it alongside the primary machine configuration when applying updates. Verify the service and licensing state:

```sh
talosctl -n <talos-node> service ext-nvidia-gridd
talosctl -n <talos-node> logs ext-nvidia-gridd
chroot /host /usr/bin/nvidia-smi -q | grep -A8 -i 'licensed product'
```

### Legacy GRID License Server

If you are using the older GRID License Server protocol rather than NVIDIA License System, you can override the daemon configuration instead of supplying an NLS token:

```yaml
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: nvidia-gridd
configFiles:
  - mountPath: /run/gridd.conf
    content: |
      ServerAddress=gridlicense.example.internal
      ServerPort=7070
      FeatureType=1
      EnableUI=FALSE
```

This legacy mode uses the GRID licensing protocol and its configured port; an arbitrary HTTPS URL is not interchangeable with a DLS/CLS endpoint. Confirm the protocol and port exposed by your server before using this mode.

The service's runtime logs and NVIDIA's `nvidia-smi -q` license status are the source of truth. A successful extension build or a running `nvidia-gridd` process alone does not prove that a license was acquired.
