# Reproducible Talos v1.13.10 amd64 kernel build inputs

This document pins the kernel ABI inputs for the first build target. It is not a generic `1.13.x` kernel tree.

## Immutable source pins

| Input | Value |
|---|---|
| Talos release | `v1.13.10` |
| Architecture | `amd64` / `x86_64` |
| Linux source | `6.18.48` |
| `siderolabs/pkgs` commit | `9b044c593c71b0ea6deb9985b7907e008b91220c` |
| Kernel config | `kernel/build/config-amd64` at that commit |
| Kernel config blob SHA | `4c198a3dbf1168913c267420523e7fd2157c4582` |
| LLVM image | `ghcr.io/siderolabs/llvm:v1.13.0-12-gc70be08` |
| Musl toolchain image | `ghcr.io/siderolabs/toolchain-musl:v1.13.0-6-g3d4094f` |
| bldr frontend in upstream Pkgfile | `ghcr.io/siderolabs/bldr:v0.5.6` |
| Clang / LLD recorded in config | `22.1.2` |
| Linux source SHA-256 | `5ebdadb10a4b5708fc6b1c457764a110bc49f8150cc3502c59b921ead8c6fc8c` |
| Linux source SHA-512 | `711e08958a8a4c39206018d0222687dc5a01845a9226ae44f7d3f0cfcea76caae041cee958dfe8c0cfc8c728a5a2241b29018ccf1b7593b9615c27057d2628c4` |

The kernel config sets `CONFIG_LOCALVERSION="-talos"`, ThinLTO, and records Clang 22.1.2. The exact release string must still be read from the built tree's `include/config/kernel.release`; do not hard-code a guessed `uname -r` value.

## Source references

- Talos release: https://github.com/siderolabs/talos/releases/tag/v1.13.10
- Pinned pkgs commit: https://github.com/siderolabs/pkgs/tree/9b044c593c71b0ea6deb9985b7907e008b91220c
- Kernel build package: https://github.com/siderolabs/pkgs/blob/9b044c593c71b0ea6deb9985b7907e008b91220c/kernel/build/pkg.yaml
- Kernel prepare package: https://github.com/siderolabs/pkgs/blob/9b044c593c71b0ea6deb9985b7907e008b91220c/kernel/prepare/pkg.yaml
- Kernel config: https://github.com/siderolabs/pkgs/blob/9b044c593c71b0ea6deb9985b7907e008b91220c/kernel/build/config-amd64
- Root Pkgfile pins the toolchain image tags and Linux source checksums.

## Generate the exact build tree and Module.symvers

`Module.symvers` is a generated output, not a separate downloadable release artifact. The pinned upstream `kernel-build` stage runs the full kernel build and `make modules`, then exports `/src` and `/toolchain`. This is the appropriate source for external module builds.

```sh
git clone https://github.com/siderolabs/pkgs.git
cd pkgs
git checkout 9b044c593c71b0ea6deb9985b7907e008b91220c
docker buildx create --name talos-kernel --use 2>/dev/null || docker buildx use talos-kernel
make local-kernel-build PLATFORM=linux/amd64 DEST="$PWD/_out/kernel-build"
test -s _out/kernel-build/src/Module.symvers
cat _out/kernel-build/src/include/config/kernel.release
sha256sum _out/kernel-build/src/Module.symvers
sha256sum _out/kernel-build/src/.config
```

The upstream `kernel-build` package uses the pinned `LLVM_IMAGE:TOOLS_REV` dependency and runs `make -j$(nproc)` plus `make modules`. Preserve the exported `/src` and `/toolchain` together. Do not substitute distribution headers, a vanilla kernel config, GCC, or another LLVM image.

## NVIDIA module build requirements

Use the authorized GRID installer `NVIDIA-Linux-x86_64-535.161.07-grid.run`, not the public non-GRID datacenter installer. Extract its kernel source and build it in the same bldr environment that provides the pinned `/src` kernel tree and LLVM toolchain. The upstream Talos proprietary module recipe uses `LD=ld.lld`, `OBJDUMP=llvm-objdump`, and `SYSSRC=/src`; the vGPU GRID package must be built and tested separately rather than assuming the standard datacenter archive is byte-for-byte equivalent.

Before packaging, require all of the following:

1. `modinfo -F vermagic` matches the built tree's `include/config/kernel.release`.
2. Module symbol versions resolve against the exact generated `Module.symvers`.
3. Module signature policy is compatible with the Talos kernel and the produced modules.
4. Kernel modules and all required userspace components are from the same GRID guest driver version.
5. Runtime test on Talos v1.13.10 with an assigned vGPU succeeds; inspect NVRM logs and test CUDA or the intended graphics workload.

## Why the build is not run automatically here

The GRID `.run` package is gated by NVIDIA's Licensing Portal and cannot be fetched anonymously. The public NVIDIA datacenter driver archive contains a similarly-versioned ordinary installer, not proof of the licensed vGPU GRID guest package. Until the authorized GRID file is supplied as a private build input, compiling a different package would produce the wrong artifact.