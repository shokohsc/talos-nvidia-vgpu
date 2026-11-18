# NVIDIA Container Toolkit on Talos

The `nvidia-container-toolkit` system extension packages NVIDIA Container Toolkit
1.17.8 and `libnvidia-container` 1.17.8 as a standalone extension. It includes
`nvidia-container-runtime`, `nvidia-container-runtime-hook`, `nvidia-ctk`,
`nvidia-cdi-hook`, `nvidia-container-cli`, and `libnvidia-container`.

It deliberately does **not** install an NVIDIA kernel driver, NVML, CUDA,
`nvidia-gridd`, or NVIDIA driver userspace. It is intended to coexist with the
GRID 535.161.07 driver extension in this repository.

## libc compatibility

Talos uses musl, but the proprietary NVIDIA GRID guest libraries (including
NVML and CUDA) are glibc-linked. The Toolkit runtime loads those libraries
dynamically when discovering devices. A musl-linked Toolkit binary cannot
reliably load the glibc driver libraries; adding their directory to
`LD_LIBRARY_PATH` does not bridge the libc ABI.

For that reason, the Toolkit payload is built in a glibc-based Debian builder.
The extension carries the required glibc loader/runtime libraries privately
under `/usr/local/lib` and sets the runtime executables' interpreter to that
location. It does not replace Talos' musl loader or libc. The extension build
runs the packaged runtime through the bundled glibc loader and checks that its
direct shared-library dependencies resolve.

The optional NVIDIA sandbox-utils discovery library is not bundled by this
extension. NVIDIA Container Toolkit 1.17.8 treats its absence as an optional
discovery feature and logs that it is unavailable; it is not the NVML library
and should not be confused with the GRID driver libraries.

## Containerd registration

The extension installs
`/etc/cri/conf.d/10-nvidia-container-runtime.part` with the named
`nvidia` runtime handler. It does not change containerd's default runtime.
Kubernetes selects it only for pods that use the already-installed
`RuntimeClass` with `handler: nvidia`.

No additional machine-configuration patch is required for runtime registration.
Do not also apply the older manual runtime patch; duplicate containerd runtime
tables can cause containerd configuration errors during boot.

## Build and install

Build both OCI extensions for the same Talos release and add both to the
Talos Image Factory schematic:

- `nvidia-vgpu-guest` (GRID 535.161.07 driver and licensing service)
- `nvidia-container-toolkit` (glibc-linked runtime and libnvidia-container)

The Toolkit builder fetches and pins the upstream v1.17.8 sources plus the
nvidia-modprobe 550.54.14 source. Run `make toolkit-build` to build the
glibc-linked payload and package the Talos extension. Docker Buildx is required.

The device plugin and the Kubernetes RuntimeClass are separate cluster
components and remain the responsibility of the cluster configuration.

## Validation

After installing the extension and rebooting, verify on the Talos node:

```sh
talosctl -n <node> -e <endpoint> ls /usr/local/bin/nvidia-container-runtime
talosctl -n <node> -e <endpoint> ls /usr/local/bin/nvidia-container-cli
talosctl -n <node> -e <endpoint> ls /usr/local/lib/ld-linux-x86-64.so.2
talosctl -n <node> -e <endpoint> ls /etc/cri/conf.d
```

Then run a pod using `runtimeClassName: nvidia` and a GPU resource request.
Confirm the pod can execute `nvidia-smi` and a real CUDA workload. A successful
package build or runtime registration alone does not establish vGPU runtime
compatibility.
