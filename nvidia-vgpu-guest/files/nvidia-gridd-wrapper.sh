#!/bin/sh
set -eu

# The extension-service rootfs is intentionally minimal. It contains the
# BusyBox binary, but not the usual applet symlinks or GNU coreutils. Invoke
# BusyBox explicitly rather than relying on PATH lookup for mkdir/cp/chmod/etc.
busybox=/bin/busybox
if [ ! -x "${busybox}" ]; then
  echo "Missing BusyBox runtime at ${busybox}" >&2
  exit 127
fi

token_target=/etc/nvidia/ClientConfigToken/client_configuration_token.tok
gridd_config=/etc/nvidia/gridd.conf
dls_url="${NVIDIA_DLS_URL:-https://dls.home.arpa}"

# Keep the licensing configuration inside the service's private rootfs.
# The package normally ships this file, but create a safe vGPU default if it
# is absent (for example, after a rootfs/package layout change). A runtime
# /run/gridd.conf override is reserved for legacy GRID License Server setups.
"${busybox}" mkdir -p /etc/nvidia

# NVIDIA GRID License System stores its local state under this directory.
# The service rootfs is isolated from the Talos host, so create the complete
# hierarchy here before nvidia-gridd attempts to initialize GridLicensing.
"${busybox}" mkdir -p /var/lib/nvidia/GridLicensing
if [ -s /run/gridd.conf ]; then
  "${busybox}" cp /run/gridd.conf "${gridd_config}"
  "${busybox}" chmod 0644 "${gridd_config}"
elif [ ! -s "${gridd_config}" ]; then
  printf '%s\n' \
    '# NVIDIA License System client configuration for a Talos vGPU guest.' \
    'FeatureType=1' \
    'EnableUI=FALSE' > "${gridd_config}"
  "${busybox}" chmod 0644 "${gridd_config}"
  echo "Created default NVIDIA vGPU licensing configuration"
fi

if [ ! -s "${gridd_config}" ]; then
  echo "Missing or empty ${gridd_config}" >&2
  exit 1
fi

# A legacy GRID configuration bypasses FastAPI-DLS entirely. Otherwise fetch
# a fresh NVIDIA License System token before starting the licensing daemon.
if [ ! -s /run/gridd.conf ]; then
  /usr/local/bin/nvidia-dls-token-fetcher \
    --url "${dls_url}" \
    --output "${token_target}"
  "${busybox}" chmod 0744 "${token_target}"
fi

if [ ! -s "${token_target}" ] && [ ! -s /run/gridd.conf ]; then
  echo "Missing or empty NVIDIA client token at ${token_target}" >&2
  exit 1
fi

# /var/run is pre-created in the service rootfs at image build time.
# NVIDIA uses /var/run/nvidia-gridd as a directory for runtime state.
# Never unlink it as though it were a PID file; remove only stale PID files.
if [ -f /var/run/nvidia-gridd.pid ]; then
  "${busybox}" rm -f /var/run/nvidia-gridd.pid
fi
if [ -f /var/run/nvidia-gridd/nvidia-gridd.pid ]; then
  "${busybox}" rm -f /var/run/nvidia-gridd/nvidia-gridd.pid
fi

# nvidia-gridd daemonizes on the standard Linux client. If this build keeps it
# in the foreground, this command remains the service's main process. If it
# forks, monitor the PID file so Talos restarts the service if the daemon exits.
# Preserve the loader/daemon exit status. With set -e, a foreground
# nvidia-gridd failure would otherwise terminate this wrapper before it can
# report the status; a daemonizing build returns here and is monitored below.
set +e
/usr/local/lib/ld-linux-x86-64.so.2 \
  --library-path /usr/local/lib:/usr/local/lib/nvidia/gridd:/usr/lib:/lib \
  /usr/bin/nvidia-gridd
gridd_status=$?
set -e
if [ "${gridd_status}" -ne 0 ]; then
  echo "nvidia-gridd launcher exited with status ${gridd_status}" >&2
  exit "${gridd_status}"
fi

pid=
attempt=0
while [ "${attempt}" -lt 30 ]; do
  for pidfile in /var/run/nvidia-gridd /var/run/nvidia-gridd.pid /var/run/nvidia-gridd/nvidia-gridd.pid; do
    if [ -f "${pidfile}" ] && [ -s "${pidfile}" ]; then
      pid="$("${busybox}" cat "${pidfile}")"
      break 2
    fi
  done
  attempt=$((attempt + 1))
  "${busybox}" sleep 1
done

case "${pid}" in
  ''|*[!0-9]*)
    echo "nvidia-gridd did not remain in the foreground and no valid PID file appeared" >&2
    exit 1
    ;;
esac

while "${busybox}" kill -0 "${pid}" 2>/dev/null; do
  "${busybox}" sleep 5
done

echo "nvidia-gridd process ${pid} exited" >&2
exit 1
