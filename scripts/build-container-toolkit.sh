#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive_dir="${repo_root}/nvidia-container-toolkit/sources-archive"
output_dir="${repo_root}/nvidia-container-toolkit/prebuilt"

for archive in \
  libnvidia-container-v1.17.8.tar.gz \
  nvidia-container-toolkit-v1.17.8.tar.gz \
  nvidia-modprobe-550.54.14.tar.gz; do
  if [[ ! -s "${archive_dir}/${archive}" ]]; then
    echo "Missing source archive: ${archive_dir}/${archive}" >&2
    echo "Run the source checkout/archive steps from .github/workflows/container-toolkit-build.yaml first." >&2
    exit 1
  fi
done

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

docker buildx build \
  --platform linux/amd64 \
  --file "${repo_root}/nvidia-container-toolkit/Dockerfile.glibc" \
  --target output \
  --output "type=local,dest=${output_dir}" \
  "${repo_root}"

test -x "${output_dir}/usr/local/bin/nvidia-container-runtime"
test -x "${output_dir}/usr/local/bin/nvidia-container-runtime-hook"
test -x "${output_dir}/usr/local/bin/nvidia-container-cli"
test -s "${output_dir}/usr/local/lib/libnvidia-container.so.1.17.8"
echo "Built glibc-linked NVIDIA Container Toolkit payload in ${output_dir}"
