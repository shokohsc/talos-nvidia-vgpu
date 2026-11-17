# NVIDIA Container Toolkit on Talos

The `nvidia-container-toolkit` system extension packages NVIDIA Container Toolkit
1.17.8 and `libnvidia-container` 1.17.8 as a standalone extension. It includes
`nvidia-container-runtime`, `nvidia-container-runtime-hook`, `nvidia-ctk`,
`nvidia-cdi-hook`, `nvidia-container-cli`, and `libnvidia-container`.

It deliberately does **not** install an NVIDIA kernel driver, NVML, CUDA,
`nvidia-gridd`, or NVIDIA driver userspace. It is intended to coexist with the
GRID 535.161.07 driver extension in this repository.

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
- `nvidia-container-toolkit` (runtime and libnvidia-container only)

The device plugin and the Kubernetes RuntimeClass are separate cluster
components and remain the responsibility of the cluster configuration.

## Validation

After installing the extension and rebooting, verify on the Talos node:

```sh
talosctl -n <node> -e <endpoint> ls /usr/local/bin/nvidia-container-runtime
talosctl -n <node> -e <endpoint> ls /usr/local/bin/nvidia-container-cli
talosctl -n <node> -e <endpoint> ls /etc/cri/conf.d
```

Then run a pod using `runtimeClassName: nvidia` and a GPU resource request.
Confirm the pod can execute `nvidia-smi` and a real CUDA workload. A successful
package build or runtime registration alone does not establish vGPU runtime
compatibility.
