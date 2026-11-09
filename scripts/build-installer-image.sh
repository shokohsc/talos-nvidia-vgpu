#!/usr/bin/env bash
# Build a custom Talos installer image with the official extensions plus the
# custom nvidia-vgpu extension produced by `make build`.
#
# The public Image Factory only supports official extensions, so this uses
# the imager container directly (see "Boot Assets" in the Talos docs).
#
# Required env:
#   CUSTOM_EXTENSION_REF  registry ref to push the nvidia extension to,
#                         e.g. docker.io/<user>/nvidia-vgpu:535.161.07-talos-v1.13.10
#   INSTALLER_IMAGE       registry ref for the final installer image,
#                         e.g. docker.io/<user>/metal-installer:v1.13.10
# Optional env:
#   TALOS_VERSION         default v1.13.10
#   EXTENSION_IMAGE       custom extension OCI tar, default _out/nvidia-vgpu-535.161.07-talos-v1.13.10.oci.tar
#   OUT_DIR               default _out
set -euo pipefail

TALOS_VERSION="${TALOS_VERSION:-v1.13.10}"
EXTENSION_IMAGE="${EXTENSION_IMAGE:-_out/nvidia-vgpu-535.161.07-talos-${TALOS_VERSION}.oci.tar}"
OUT_DIR="${OUT_DIR:-_out}"
: "${CUSTOM_EXTENSION_REF:?set CUSTOM_EXTENSION_REF, e.g. docker.io/<user>/nvidia-vgpu:535.161.07-talos-v1.13.10}"
: "${INSTALLER_IMAGE:?set INSTALLER_IMAGE, e.g. docker.io/<user>/metal-installer:v1.13.10}"

OFFICIAL_EXTENSIONS=(
  gvisor
  nfs-utils
  nfsd
  qemu-guest-agent
  stargz-snapshotter
  uhid
  uinput
)

test -s "$EXTENSION_IMAGE" || { echo "ERROR: $EXTENSION_IMAGE missing; run 'make build' first" >&2; exit 2; }
mkdir -p "$OUT_DIR"

crane push "$EXTENSION_IMAGE" "$CUSTOM_EXTENSION_REF"

ext_args=(--system-extension-image "$CUSTOM_EXTENSION_REF")
for name in "${OFFICIAL_EXTENSIONS[@]}"; do
  ref="$(crane export "ghcr.io/siderolabs/extensions:${TALOS_VERSION}" | tar x -O image-digests | grep -F "ghcr.io/siderolabs/${name}:" | head -1 | tr -d '[:space:]')"
  test -n "$ref" || { echo "ERROR: official extension siderolabs/$name not found for $TALOS_VERSION" >&2; exit 2; }
  ext_args+=(--system-extension-image "$ref")
done

auth_mount=()
if [ -f "$HOME/.docker/config.json" ]; then
  auth_mount=(-v "$HOME/.docker/config.json:/root/.docker/config.json:ro")
fi

docker run --rm -t \
  -v "$PWD/$OUT_DIR:/out" \
  "${auth_mount[@]}" \
  "ghcr.io/siderolabs/imager:${TALOS_VERSION}" \
  installer \
  --platform=metal \
  "${ext_args[@]}"

crane push "$OUT_DIR/metal-amd64-installer.tar" "$INSTALLER_IMAGE"
echo "Installer image: $INSTALLER_IMAGE"
