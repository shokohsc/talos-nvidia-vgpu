#!/usr/bin/env bash
set -euo pipefail

ROOTFS="${1:-dist/rootfs}"
: "${KERNEL_RELEASE:?Set KERNEL_RELEASE to the exact target Talos kernel release}"
MODULE_ROOT="$ROOTFS/usr/lib/modules/$KERNEL_RELEASE"
if [[ ! -d "$MODULE_ROOT" ]]; then
  echo "ERROR: missing module directory: $MODULE_ROOT" >&2
  exit 1
fi

find_module() {
  local name="$1"
  find "$MODULE_ROOT" -type f \( -name "$name.ko" -o -name "$name.ko.xz" -o -name "$name.ko.zst" \) -print -quit
}

for module in nvidia nvidia-uvm nvidia_uvm; do
  if [[ -z "$(find_module "$module")" ]]; then
    echo "ERROR: missing required module: $module.ko[.xz|.zst]" >&2
    exit 1
  fi
done

for module in nvidia-modeset nvidia_modeset nvidia-drm nvidia_drm; do
  if [[ -n "$(find_module "$module")" ]]; then
    echo "Found optional module: $module"
  fi
done

if command -v modinfo >/dev/null 2>&1; then
  while IFS= read -r -d '' file; do
    vermagic="$(modinfo -F vermagic "$file" 2>/dev/null || true)"
    if [[ -n "$vermagic" && "${vermagic%% *}" != "$KERNEL_RELEASE" ]]; then
      echo "ERROR: $file vermagic '$vermagic' does not match '$KERNEL_RELEASE'" >&2
      exit 1
    fi
  done < <(find "$MODULE_ROOT" -type f \( -name 'nvidia*.ko' -o -name 'nvidia*.ko.xz' -o -name 'nvidia*.ko.zst' \) -print0)
else
  echo "WARNING: modinfo not installed; vermagic check skipped" >&2
fi

echo "Artifact tree passed basic module-presence checks for $KERNEL_RELEASE."