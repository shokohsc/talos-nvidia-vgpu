# talos-nvidia-vgpu

Talos Linux system extension packaging the proprietary NVIDIA vGPU guest driver for Tesla vGPU guests.

Initial reproducible target: Talos **v1.13.10 amd64**, Linux **6.18.48**, NVIDIA vGPU guest driver **535.161.07**. This target is experimental; do not generalize its kernel ABI to other 1.13.x releases.

> **Build blocker:** the vGPU guest installer (`NVIDIA-Linux-x86_64-535.161.07-grid.run`) is distributed through NVIDIA's entitlement-only vGPU Licensing Portal. It is not the ordinary public 535.161.07 datacenter `.run` installer. No proprietary binary is stored in this repository. A module build cannot run until an authorized copy is supplied privately.

> **Compatibility warning:** NVIDIA 535.161.07 predates Linux 6.18. A successful compile is not proof of runtime compatibility. Validate module loading, NVRM initialization, vGPU enumeration, and a real workload on the exact Talos VM.

## Scope

- Guest-side proprietary modules only; Proxmox retains the vGPU Manager and host-side `nvidia-vgpu-vfio`.
- Matching userspace must come from the same GRID guest package. Do not mix versions.
- vGPU profile selection is configured on Proxmox and does not change the Talos extension build.

## Exact kernel build inputs

See [docs/kernel-build.md](docs/kernel-build.md) for the pinned `siderolabs/pkgs` commit, kernel config, source checksums, LLVM toolchain image, and `Module.symvers` generation procedure.

## NVIDIA driver package

Download the vGPU 16.4 software ZIP from the [NVIDIA Enterprise Application Hub](https://nvid.nvidia.com/dashboard/) → NVIDIA Licensing Portal → Software Downloads → Product Family: vGPU. Extract `NVIDIA-Linux-x86_64-535.161.07-grid.run`. Do not use the similarly-versioned public datacenter installer as a substitute. Store the GRID package in a private artifact image or private CI artifact; never commit it or publish it in a public registry.

## Repository layout

- `Pkgfile` and `nvidia-vgpu-guest/pkg.yaml`: bldr package definitions.
- `nvidia-vgpu-guest/manifest.yaml.tmpl`: Talos extension manifest.
- `Dockerfile.artifacts`: packages a prepared rootfs as a bldr input image.
- `scripts/validate-artifacts.sh`: checks a prepared module artifact tree.
- `.github/workflows/ci.yaml`: static checks only; it does not compile proprietary modules.

## Current build state

The repository currently defines a packaging path for an externally prepared rootfs. It does **not** yet claim to compile the GRID guest driver or produce a runtime-tested extension. The NVIDIA GRID installer is the missing build input. Once supplied, the module package/build recipe must extract its kernel source, compile against the pinned Talos build tree with the matching LLVM toolchain, install modules and matching userspace, and validate vermagic and symbol versions.

## Proxmox and Talos

Configure a full-card vGPU profile on Proxmox and assign that mediated device to the Talos VM. Example profiles previously considered are P4-8Q and P40-24Q, subject to the GPU SKU, installed vGPU Manager, and licensing. Merge `docs/talos-machine-config.yaml` into your Talos machine config only after the extension is built and validated.

## Security and licensing

NVIDIA proprietary driver installers and libraries are intentionally excluded. Do not store NVIDIA credentials, license tokens, or vendor binaries in public GitHub repositories or public registries.