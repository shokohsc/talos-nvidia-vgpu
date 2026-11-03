#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${NVIDIA_DRIVER_IMAGE:-docker.io/shokohsc/nvidia-vgpu-driver:535.161.07-grid}"
EXPECTED_VERSION="${NVIDIA_DRIVER_VERSION:-535.161.07}"
WORKDIR="${WORKDIR:-$PWD/_work/nvidia-vgpu}"
INSTALLER_DIR="$WORKDIR/installer"
METADATA="${METADATA_FILE:-$WORKDIR/driver-metadata.txt}"
EXTRACTED="${DRIVER_SOURCE_DIR:-$WORKDIR/extracted}"

command -v docker >/dev/null
command -v sha256sum >/dev/null
command -v tar >/dev/null
rm -rf "$WORKDIR" "$EXTRACTED"
mkdir -p "$INSTALLER_DIR" "$(dirname "$EXTRACTED")"

container_id=""
cleanup() {
  if [[ -n "$container_id" ]]; then docker rm -f "$container_id" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

echo "::group::Pull GRID installer image"
docker pull --platform linux/amd64 "$IMAGE"
container_id="$(docker create --platform linux/amd64 --entrypoint /bin/true "$IMAGE")"

# Stream only the .run file out of the container export; do not unpack its
# complete root filesystem onto the hosted runner.
escaped_version="${EXPECTED_VERSION//./\\.}"
mapfile -t installer_paths < <(
  docker export "$container_id" |
    tar -tf - |
    grep -E "(^|/)NVIDIA-Linux-x86_64-${escaped_version}(-grid)?\.run$"
)
if [[ "${#installer_paths[@]}" -ne 1 ]]; then
  echo "Expected exactly one NVIDIA ${EXPECTED_VERSION} .run installer in $IMAGE; found ${#installer_paths[@]}" >&2
  exit 1
fi
installer="$INSTALLER_DIR/$(basename "${installer_paths[0]}")"
docker export "$container_id" | tar -xOf - "${installer_paths[0]}" > "$installer"
chmod +x "$installer"
installer_sha256="$(sha256sum "$installer" | awk '{print $1}')"

docker rm -f "$container_id" >/dev/null
container_id=""
docker image rm "$IMAGE" >/dev/null 2>&1 || true
echo "::endgroup::"

echo "Checking installer: $installer"
"$installer" --check
"$installer" --info | tee "$WORKDIR/installer-info.txt"
if ! grep -Fq "$EXPECTED_VERSION" "$WORKDIR/installer-info.txt" && [[ "$(basename "$installer")" != *"$EXPECTED_VERSION"* ]]; then
  echo "Installer metadata/name does not match expected version $EXPECTED_VERSION" >&2
  exit 1
fi

echo "Extracting GRID installer payload directly to $EXTRACTED"
"$installer" --extract-only --target "$EXTRACTED"

# Some GRID runfile repacks keep the shared NVIDIA headers under
# kernel-open/common while the proprietary module Makefiles expect them at
# kernel/common. Populate that shared include tree when it is absent.
if [[ ! -d "$EXTRACTED/kernel/common/inc" && -d "$EXTRACTED/kernel-open/common/inc" ]]; then
  mkdir -p "$EXTRACTED/kernel/common"
  cp -a "$EXTRACTED/kernel-open/common/." "$EXTRACTED/kernel/common/"
fi

for header in os-interface.h nv-firmware.h nv-dmabuf.h nv-pci-types.h; do
  if [[ ! -s "$EXTRACTED/kernel/common/inc/$header" ]]; then
    echo "Missing NVIDIA kernel header after extraction: kernel/common/inc/$header" >&2
    echo "Available common include directories:" >&2
    find "$EXTRACTED" -path '*/common/inc' -type d -print >&2
    exit 1
  fi
done

rm -f "$installer"
rmdir "$INSTALLER_DIR" 2>/dev/null || true

test -s "$EXTRACTED/kernel/Makefile"
test -x "$EXTRACTED/nvidia-installer"
echo "Extracted top-level entries:"
ls -la "$EXTRACTED"
echo "NVIDIA userspace payload candidates:"
find "$EXTRACTED" -maxdepth 4 \( -name 'nvidia-smi' -o -name 'libnvidia-ml.so*' -o -name 'libcuda.so*' \) -print

{
  echo "image=$IMAGE"
  echo "installer=$(basename "${installer_paths[0]}")"
  echo "installer_sha256=$installer_sha256"
  echo "driver_version=$EXPECTED_VERSION"
  echo "extracted_kernel_source=$EXTRACTED/kernel"
  echo "extracted_tree_size=$(du -sh "$EXTRACTED" | awk '{print $1}')"
} | tee "$METADATA"

echo "GRID installer extraction succeeded: $EXTRACTED"
