#!/usr/bin/env bash
# Build a custom Talos installer image with the official extensions plus the
# custom nvidia-vgpu extension produced by `make build`.
#
# The public Image Factory only supports official extensions, so this uses
# the imager container directly with a profile.yaml (see "Boot Assets" in the
# Talos docs).
#
# Optional env:
#   TALOS_VERSION         default v1.13.10
#   EXTENSION_IMAGE       nvidia extension image tar (docker-save format),
#                         default _out/nvidia-vgpu-535.161.07-talos-v1.13.10.oci.tar
#   OUT_DIR               default _out
#   CUSTOM_EXTENSION_REF  if set, the extension tar is pushed here with crane
#                         and referenced by imageRef; if unset, the local tar
#                         is used via tarballPath (no registry needed)
#   INSTALLER_IMAGE       if set, the built installer tar is pushed here,
#                         e.g. ghcr.io/<user>/metal-installer:v1.13.10
set -euo pipefail

if ! command -v crane >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64) crane_arch=x86_64 ;;
    aarch64) crane_arch=arm64 ;;
    *) echo "ERROR: unsupported arch $(uname -m) for crane install" >&2; exit 2 ;;
  esac
  crane_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_${crane_arch}.tar.gz" \
    | tar -xz -C "$crane_dir" crane
  export PATH="$crane_dir:$PATH"
fi

TALOS_VERSION="${TALOS_VERSION:-v1.13.10}"
EXTENSION_IMAGE="${EXTENSION_IMAGE:-_out/nvidia-vgpu-535.161.07-talos-${TALOS_VERSION}.oci.tar}"
OUT_DIR="${OUT_DIR:-_out}"

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

if [ -n "${CUSTOM_EXTENSION_REF:-}" ]; then
  crane push "$EXTENSION_IMAGE" "$CUSTOM_EXTENSION_REF"
  custom_ext="    - imageRef: ${CUSTOM_EXTENSION_REF}"
else
  # tarballPath expects a docker-save tarball; build with
  # --output type=docker,dest=... when EXTENSION_IMAGE is not an OCI layout.
  custom_ext="    - tarballPath: /extension/ext.tar"
fi

profile="$OUT_DIR/installer-profile.yaml"
{
  echo "arch: amd64"
  echo "platform: metal"
  echo "secureboot: false"
  echo "version: ${TALOS_VERSION}"
  echo "input:"
  echo "  kernel:"
  echo "    path: /usr/install/amd64/vmlinuz"
  echo "  initramfs:"
  echo "    path: /usr/install/amd64/initramfs.xz"
  echo "  baseInstaller:"
  echo "    imageRef: ghcr.io/siderolabs/installer:${TALOS_VERSION}"
  echo "  systemExtensions:"
  for name in "${OFFICIAL_EXTENSIONS[@]}"; do
    ref="$(crane export "ghcr.io/siderolabs/extensions:${TALOS_VERSION}" | tar x -O image-digests | grep -F "ghcr.io/siderolabs/${name}:" | head -1 | tr -d '[:space:]')"
    test -n "$ref" || { echo "ERROR: official extension siderolabs/$name not found for $TALOS_VERSION" >&2; exit 2; }
    echo "    - imageRef: ${ref}"
  done
  echo "$custom_ext"
  echo "output:"
  echo "  kind: installer"
  echo "  outFormat: raw"
} > "$profile"

auth_mount=()
if [ -f "$HOME/.docker/config.json" ]; then
  auth_mount=(-v "$HOME/.docker/config.json:/root/.docker/config.json:ro")
fi

docker run --rm -i \
  -v "$PWD/$OUT_DIR:/out" \
  -v "$PWD/$EXTENSION_IMAGE:/extension/ext.tar:ro" \
  "${auth_mount[@]}" \
  "ghcr.io/siderolabs/imager:${TALOS_VERSION}" \
  - < "$profile"

if [ -n "${INSTALLER_IMAGE:-}" ]; then
  crane push "$OUT_DIR/metal-amd64-installer.tar" "$INSTALLER_IMAGE"
  echo "Installer image: $INSTALLER_IMAGE"
else
  echo "Installer tar: $OUT_DIR/metal-amd64-installer.tar"
fi
