# talos-nvidia-vgpu

Talos Linux system extension packaging the proprietary NVIDIA vGPU guest driver for Tesla vGPU guests.

Target: Talos 1.13.x and later, NVIDIA vGPU guest driver 535.161.07, x86_64. Build one image per exact Talos release and kernel ABI.

> Experimental: driver 535.161.07 predates Linux 6.18. Some Talos 1.13 builds use a Linux 6.18 kernel. A successful package build does not prove runtime compatibility. Do not deploy until module load, NVRM initialization, vGPU enumeration, and workload tests pass.

## Scope

- Guest-side proprietary modules: nvidia, nvidia_uvm, nvidia_modeset, and nvidia_drm when present.
- Matching NVIDIA userspace libraries and tools may be included in the artifact rootfs.
- Proxmox owns the vGPU Manager, mediated-device creation, and vGPU assignment.
- Do not install nvidia-vgpu-vfio in Talos; it is host-side.
- Profile selection is a Proxmox concern, not a different Talos extension build.

## Layout

- Pkgfile and nvidia-vgpu-guest/pkg.yaml: bldr package.
- nvidia-vgpu-guest/manifest.yaml.tmpl: Talos extension manifest.
- Dockerfile.artifacts: packages a prepared rootfs as a bldr input image.
- scripts/validate-artifacts.sh: fail-closed module artifact checks.
- .github/workflows/ci.yaml: static validation without proprietary files.

## Artifact contract

Prepare dist/rootfs with the vendor guest driver files at final Talos paths. At minimum, place nvidia.ko and nvidia-uvm.ko (or nvidia_uvm.ko) under usr/lib/modules/<KERNEL_RELEASE>/. Include nvidia-modeset and nvidia-drm modules when built. Compressed .ko.xz and .ko.zst files are accepted.

Include matching userspace components under supported extension paths when required, such as usr/bin/nvidia-smi, usr/lib, and usr/local. Never mix userspace from another driver release.

The module build must use the exact Talos kernel source/build tree, generated kernel config, Module.symvers, compiler/toolchain, and architecture. Generic Linux headers are not sufficient. Verify module vermagic and symbol-version compatibility.

## Build

Requirements: Docker Buildx, a registry, and NVIDIA driver artifacts obtained through an authorized NVIDIA channel.

1. Prepare dist/rootfs using the licensed NVIDIA 535.161.07 guest driver and exact Talos kernel build inputs.
2. Run: make validate-artifacts KERNEL_RELEASE=<exact-kernel-release>
3. Build and push the artifact image: make push-artifacts ARTIFACT_IMAGE=ghcr.io/<owner>/nvidia-vgpu-guest-artifacts:<tag>
4. Build the extension:

   make build ARTIFACT_IMAGE=ghcr.io/<owner>/nvidia-vgpu-guest-artifacts:<tag> TALOS_VERSION=v1.13.x KERNEL_RELEASE=<exact-kernel-release> EXTENSION_IMAGE=ghcr.io/<owner>/nvidia-vgpu-guest:<tag>

The bldr frontend is pinned in Pkgfile. The artifact image is an input dependency and is not published by this repository.

## Install and verify

Add the built extension image to a Talos Image Factory schematic or custom installer image. Pin the extension by digest in production. This extension is not installed by Kubernetes or the NVIDIA device plugin.

After boot, inspect Talos dmesg for NVIDIA/NVRM messages. Confirm nvidia-smi sees the assigned vGPU from a compatible diagnostic environment. Then deploy a device plugin/CDI setup appropriate to the container runtime. The NVIDIA Container Toolkit and Kubernetes device plugin are separate from this kernel-module extension.

## Proxmox profiles

Configure one full-card vGPU profile on Proxmox and assign it to the Talos VM. P4-8Q and P40-24Q are example profiles previously considered for Tesla P4/P40, subject to the installed vGPU Manager profile list, GPU SKU, and licensing. The profile does not alter this extension.

## Compatibility policy

- Build a distinct extension for each exact Talos release/kernel ABI.
- Keep driver version fixed at 535.161.07 unless intentionally upgraded.
- Record Talos version, kernel release, kernel config hash, compiler version, Module.symvers hash, and driver package checksum.
- A bldr build proves packaging only. Runtime acceptance requires module load, NVRM initialization, vGPU enumeration, and a real workload test.
- Do not claim a Talos 1.13.x combination is supported until runtime tests pass.

## Licensing and secrets

NVIDIA driver installers and proprietary libraries are not committed here. Store vendor packages in a private artifact store or authorized workflow. Never put NVIDIA credentials or license tokens in Git, build arguments, or public CI logs.