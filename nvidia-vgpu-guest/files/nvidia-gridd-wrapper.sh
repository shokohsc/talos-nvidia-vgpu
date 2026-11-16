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
dls_url="${NVIDIA_DLS_URL:-https://dls.home.arpa}"

# A legacy GRID configuration bypasses FastAPI-DLS entirely. Otherwise fetch
# a fresh NVIDIA License System token before starting the licensing daemon.
# The Go fetcher creates the token directory itself using os.MkdirAll.
if [ -s /run/gridd.conf ]; then
  "${busybox}" cp /run/gridd.conf /etc/nvidia/gridd.conf
  "${busybox}" chmod 0644 /etc/nvidia/gridd.conf
else
  /usr/local/bin/nvidia-dls-token-fetcher \
    --url "${dls_url}" \
    --output "${token_target}"
  "${busybox}" chmod 0744 "${token_target}"
fi

if [ ! -s /etc/nvidia/gridd.conf ]; then
  echo "Missing /etc/nvidia/gridd.conf" >&2
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
/usr/local/lib/ld-linux-x86-64.so.2 \
  --library-path /usr/local/lib:/usr/local/lib/nvidia/gridd:/usr/lib:/lib \
  /usr/bin/nvidia-gridd

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
