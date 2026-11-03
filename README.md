# talos-nvidia-vgpu

Talos Linux system extension packaging the NVIDIA vGPU guest driver for Tesla vGPU guests.

Initial reproducible target: Talos **v1.13.10 amd64**, Linux **6.18.48**, NVIDIA vGPU guest driver **535.161.07**. Build a distinct extension for each exact Talos kernel ABI.

> **Compatibility warning:** NVIDIA 535.161.07 predates Linux 6.18. A successful compile is not proof of runtime compatibility. Validate module loading, NVRM initialization, vGPU enumeration, and a real workload on the exact Talos VM.

## Scope

- Guest-side proprietary modules only; Proxmox retains the vGPU Manager and host-side `nvidia-vgpu-vfio`.
- Matching userspace must come from the same GRID guest package.
- vGPU profile selection is configured on Proxmox and does not change the Talos extension build.

## Driver input and CI extraction

The CI consumes the public, version-pinned image:

`docker.io/shokohsc/nvidia-vgpu-driver:535.161.07-grid`

The workflow `.github/workflows/driver-build.yaml` runs `scripts/extract-driver.sh`, which:

1. Pulls the image for `linux/amd64` and exports its filesystem without running its entrypoint.
2. Locates exactly one `NVIDIA-Linux-x86_64-535.161.07-grid.run`.
3. Runs the vendor archive integrity check (`--check`) and records installer metadata.
4. Extracts the installer with `--extract-only --target`.
5. Checks for the kernel interface source tree and matching driver version.

The proprietary payload is extracted only on the ephemeral GitHub Actions runner. It is not committed to Git or uploaded as a workflow artifact.

Run the extraction locally with Docker installed:

```sh
./scripts/extract-driver.sh
```

This workflow currently validates the installer extraction stage; it does not claim to produce a Talos extension yet. The subsequent module build must use the exact kernel build tree and LLVM toolchain documented below.

## Exact kernel build inputs

See [docs/kernel-build.md](docs/kernel-build.md) for the pinned `siderolabs/pkgs` commit, kernel config, source checksums, LLVM toolchain image, and `Module.symvers` generation procedure.

## Proxmox and Talos

Configure a full-card vGPU profile on Proxmox and assign that mediated device to the Talos VM. P4-8Q and P40-24Q are candidate profiles only; confirm availability against the installed vGPU Manager, GPU SKU, and licensing. Do not install host-side `nvidia-vgpu-vfio` in Talos.

## Validation status

A bldr packaging build does not prove runtime compatibility. Before deployment, validate module vermagic, symbol versions against the exact `Module.symvers`, signature policy, matching userspace, module load, NVRM initialization, vGPU enumeration, and a real workload.
