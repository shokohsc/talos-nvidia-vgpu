# NVIDIA containerd runtime on Talos

The vGPU guest driver and `nvidia-gridd` licensing service do not register an
OCI runtime with containerd. This patch adds the named `nvidia` runtime handler
that Kubernetes selects through a `RuntimeClass` whose `handler` is `nvidia`.

This is intentionally separate from the driver build: it does not install or
package NVIDIA Container Toolkit, the NVIDIA device plugin, or a RuntimeClass.
Those components must already be present.

## Requirements

- Talos Linux v1.13.x using containerd 2.x.
- The NVIDIA vGPU guest driver and matching userspace installed on the node.
- NVIDIA Container Toolkit installed on the host, with
  `/usr/local/bin/nvidia-container-runtime` executable.
- A Kubernetes RuntimeClass named `nvidia` with `handler: nvidia`.
- The NVIDIA device plugin installed and configured for the same driver.

Check the runtime executable before applying the patch:

```sh
talosctl -n <node> -e <endpoint> ls /usr/local/bin/nvidia-container-runtime
```

If your toolkit extension installs the binary at a different path, change
`BinaryName` in the patch to that exact host path. Do not point it into the
private `nvidia-gridd` service rootfs.

## Apply

The example machine-config patch is
[`examples/talos-nvidia-containerd-runtime.patch.yaml`](../examples/talos-nvidia-containerd-runtime.patch.yaml).

Merge the `machine.files` entry into the machine configuration for GPU
workers only. Keep any existing `machine.files` entries; do not replace the
whole list. The patch writes a separate
`/etc/cri/conf.d/30-nvidia-runtime.part` fragment so it does not overwrite
Talos' generated CRI configuration or the common customization fragment.

Talos merges the fragment into containerd's CRI configuration. Applying the
machine configuration causes the CRI service to reload its configuration;
a manual containerd restart or changing the default runtime should not be
necessary.

The fragment registers:

```toml
[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  privileged_without_host_devices = false

  [plugins."io.containerd.cri.v1.runtime".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/local/bin/nvidia-container-runtime"
```

Do **not** set `default_runtime_name = "nvidia"` when using a dedicated
RuntimeClass. Kubernetes selects this handler only for pods that specify
`runtimeClassName: nvidia`; all other pods continue using the default runtime.

## Verify

1. Confirm the runtime is registered in the node's merged CRI configuration.
2. Confirm the `nvidia` RuntimeClass exists and has `handler: nvidia`.
3. Run a GPU test pod with `runtimeClassName: nvidia` and a GPU resource
   request, then check `nvidia-smi` inside that pod.
4. Confirm the node advertises `nvidia.com/gpu` and that the pod reaches
   `Running`.

A successful containerd configuration reload alone does not prove GPU
injection works. Validate an actual workload on the vGPU node.
