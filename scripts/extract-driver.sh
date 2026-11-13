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
command -v curl >/dev/null
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

# nvidia-modprobe is published by NVIDIA as a separate source archive. Pin
# the exact GRID driver version and verify NVIDIA's published SHA-256 before
# placing the source alongside the extracted GRID payload for the extension build.
NVIDIA_MODPROBE_VERSION="535.161.07"
NVIDIA_MODPROBE_SHA256="8f20b547ca6cdf51ef6bfde161d3c0438c6d9f16efe7f349134e6a686c2f4377"
NVIDIA_MODPROBE_ARCHIVE="nvidia-modprobe-${NVIDIA_MODPROBE_VERSION}.tar.bz2"
NVIDIA_MODPROBE_URL="https://download.nvidia.com/XFree86/nvidia-modprobe/${NVIDIA_MODPROBE_ARCHIVE}"
NVIDIA_MODPROBE_DIR="$EXTRACTED/nvidia-modprobe-src"
mkdir -p "$NVIDIA_MODPROBE_DIR"
curl --fail --location --retry 3 --retry-all-errors \
  "$NVIDIA_MODPROBE_URL" --output "$WORKDIR/$NVIDIA_MODPROBE_ARCHIVE"
printf '%s  %s\\n' "$NVIDIA_MODPROBE_SHA256" "$WORKDIR/$NVIDIA_MODPROBE_ARCHIVE" \
  | sha256sum --check
tar -xjf "$WORKDIR/$NVIDIA_MODPROBE_ARCHIVE" -C "$NVIDIA_MODPROBE_DIR"
modprobe_makefile="$(find "$NVIDIA_MODPROBE_DIR" -maxdepth 3 -type f -name Makefile -print -quit)"
test -n "$modprobe_makefile" || {
  echo "NVIDIA nvidia-modprobe source archive does not contain a Makefile" >&2
  exit 1
}
modprobe_source_dir="${modprobe_makefile%/Makefile}"
if [[ "$modprobe_source_dir" != "$NVIDIA_MODPROBE_DIR" ]]; then
  cp -a "$modprobe_source_dir/." "$NVIDIA_MODPROBE_DIR/"
fi
grep -Eq '^NVIDIA_VERSION[[:space:]]*=[[:space:]]*535\\.161\\.07([[:space:]]|$)' \
  "$NVIDIA_MODPROBE_DIR/version.mk" || {
  echo "nvidia-modprobe source version does not match GRID $NVIDIA_MODPROBE_VERSION" >&2
  exit 1
}
echo "Verified NVIDIA nvidia-modprobe source $NVIDIA_MODPROBE_VERSION"

# Keep the proprietary and open-kernel source trees separate. Do not
# synthesize kernel/common by copying headers from kernel-open/common: their
# interfaces are not interchangeable. Record the real installer layout so the
# proprietary build can be corrected against the files NVIDIA actually ships.
{
  echo "=== Extracted source directories (depth <= 4) ==="
  find "$EXTRACTED" -maxdepth 4 -type d -print | sort
  echo
  echo "=== Relevant NVIDIA headers (all source trees) ==="
  find "$EXTRACTED" -type f \( \
    -name os-interface.h -o -name nv-firmware.h -o -name nv-dmabuf.h -o \
    -name nv-pci-types.h -o -name nv-linux.h -o -name nvtypes.h -o \
    -name conftest.h -o -name nv.h -o -name nvstatus.h \) -print | sort
  echo
  echo "=== Kernel build entrypoints ==="
  for file in kernel/Makefile kernel/Kbuild kernel/nvidia/Makefile kernel-open/Makefile kernel-open/Kbuild; do
    if [[ -f "$EXTRACTED/$file" ]]; then
      echo "--- $file"
      sed -n '1,180p' "$EXTRACTED/$file"
    fi
  done
} | tee "$WORKDIR/source-layout.txt"


rm -f "$installer"
rmdir "$INSTALLER_DIR" 2>/dev/null || true

test -s "$EXTRACTED/kernel/Makefile"
test -x "$EXTRACTED/nvidia-installer"
echo "Extracted top-level entries:"
ls -la "$EXTRACTED"
echo "NVIDIA userspace payload candidates:"
find "$EXTRACTED" -maxdepth 5 \( -name 'nvidia-smi' -o -name 'nvidia-modprobe' -o -name 'libnvidia-ml.so*' -o -name 'libcuda.so*' \) -print

{
  echo "image=$IMAGE"
  echo "installer=$(basename "${installer_paths[0]}")"
  echo "installer_sha256=$installer_sha256"
  echo "driver_version=$EXPECTED_VERSION"
  echo "extracted_kernel_source=$EXTRACTED/kernel"
  echo "extracted_tree_size=$(du -sh "$EXTRACTED" | awk '{print $1}')"
} | tee "$METADATA"

echo "GRID installer extraction succeeded: $EXTRACTED"
