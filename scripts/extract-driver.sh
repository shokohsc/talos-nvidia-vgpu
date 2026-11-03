#!/usr/bin/env bash
set -Eeuo pipefail
IMAGE="\${NVIDIA_DRIVER_IMAGE:-docker.io/shokohsc/nvidia-vgpu-driver:535.161.07-grid}"
EXPECTED_VERSION="\${NVIDIA_DRIVER_VERSION:-535.161.07}"
WORKDIR="\${WORKDIR:-$PWD/_work/nvidia-vgpu}"
ROOTFS="$WORKDIR/image-root"
EXTRACTED="$WORKDIR/extracted"
METADATA="\${METADATA_FILE:-$WORKDIR/driver-metadata.txt}"
command -v docker >/dev/null
command -v sha256sum >/dev/null
rm -rf "$WORKDIR"
mkdir -p "$ROOTFS" "$EXTRACTED"

echo "::group::Pull installer image"
docker pull --platform linux/amd64 "$IMAGE"
container_id="$(docker create --platform linux/amd64 "$IMAGE")"
cleanup() { docker rm -f "$container_id" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker export "$container_id" | tar -xf - -C "$ROOTFS"
echo "Installer files found in image:"
find "$ROOTFS" -type f -name '*.run' -print
echo "::endgroup::"

mapfile -d '' installers < <(find "$ROOTFS" -type f -name '*.run' -print0)
if [[ "\${#installers[@]}" -ne 1 ]]; then
  echo "Expected exactly one .run installer in $IMAGE; found \${#installers[@]}" >&2
  find "$ROOTFS" -maxdepth 5 -type f | head -200 >&2 || true
  exit 1
fi

installer="\${installers[0]}"
echo "Checking installer: $installer"
chmod +x "$installer"
"$installer" --check
"$installer" --info | tee "$WORKDIR/installer-info.txt"
if ! grep -Fq "$EXPECTED_VERSION" "$WORKDIR/installer-info.txt" && [[ "$(basename "$installer")" != *"$EXPECTED_VERSION"* ]]; then
  echo "Installer metadata/name does not match expected version $EXPECTED_VERSION" >&2
  exit 1
fi

echo "Extracting GRID installer payload"
"$installer" --extract-only --target "$EXTRACTED"
test -s "$EXTRACTED/kernel/Makefile"
test -x "$EXTRACTED/nvidia-installer"
if [[ ! -d "$EXTRACTED/lib" && ! -d "$EXTRACTED/lib64" ]]; then
  echo "Expected lib/ or lib64/ in extracted installer" >&2
  find "$EXTRACTED" -maxdepth 2 -type d -print >&2
  exit 1
fi

{
  echo "image=$IMAGE"
  echo "installer=$(basename "$installer")"
  echo "installer_sha256=$(sha256sum "$installer" | awk '{print $1}')"
  echo "driver_version=$EXPECTED_VERSION"
  echo "extracted_kernel_source=$EXTRACTED/kernel"
  echo "extracted_tree_size=$(du -sh "$EXTRACTED" | awk '{print $1}')"
} | tee "$METADATA"

if [[ -n "\${DRIVER_SOURCE_DIR:-}" ]]; then
  rm -rf "$DRIVER_SOURCE_DIR"
  mkdir -p "$(dirname "$DRIVER_SOURCE_DIR")"
  cp -a "$EXTRACTED" "$DRIVER_SOURCE_DIR"
  echo "Copied extracted GRID driver source to $DRIVER_SOURCE_DIR"
fi

echo "GRID installer extraction succeeded: $EXTRACTED"
