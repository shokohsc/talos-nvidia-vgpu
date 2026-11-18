#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive_dir="${repo_root}/nvidia-container-toolkit/sources-archive"
output_dir="${repo_root}/nvidia-container-toolkit/prebuilt"
source_dir="${repo_root}/_out/toolkit-sources"

mkdir -p "${archive_dir}"
if [[ ! -s "${archive_dir}/libnvidia-container-v1.17.8.tar.gz" ||
      ! -s "${archive_dir}/nvidia-container-toolkit-v1.17.8.tar.gz" ||
      ! -s "${archive_dir}/nvidia-modprobe-550.54.14.tar.gz" ]]; then
  rm -rf "${source_dir}"
  mkdir -p "${source_dir}"
  git clone --depth 1 --branch v1.17.8 https://github.com/NVIDIA/libnvidia-container.git "${source_dir}/libnvidia-container"
  git clone --depth 1 --branch v1.17.8 https://github.com/NVIDIA/nvidia-container-toolkit.git "${source_dir}/nvidia-container-toolkit"
  git clone --depth 1 --branch 550.54.14 https://github.com/NVIDIA/nvidia-modprobe.git "${source_dir}/nvidia-modprobe"
  git -C "${source_dir}/libnvidia-container" archive --format=tar HEAD | gzip -n > "${archive_dir}/libnvidia-container-v1.17.8.tar.gz"
  git -C "${source_dir}/nvidia-container-toolkit" archive --format=tar HEAD | gzip -n > "${archive_dir}/nvidia-container-toolkit-v1.17.8.tar.gz"
  git -C "${source_dir}/nvidia-modprobe" archive --format=tar HEAD | gzip -n > "${archive_dir}/nvidia-modprobe-550.54.14.tar.gz"
fi

for archive in \
  libnvidia-container-v1.17.8.tar.gz \
  nvidia-container-toolkit-v1.17.8.tar.gz \
  nvidia-modprobe-550.54.14.tar.gz; do
  test -s "${archive_dir}/${archive}"
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
