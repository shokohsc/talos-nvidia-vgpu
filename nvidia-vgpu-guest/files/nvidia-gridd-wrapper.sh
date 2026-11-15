#!/bin/sh
set -eu

token_source=/run/nvidia-client-token.tok
token_dir=/etc/nvidia/ClientConfigToken
token_target="${token_dir}/client_configuration_token.tok"

# ExtensionServiceConfig files are mounted read-only. Copy the token into the
# service container's writable rootfs and apply NVIDIA's required file mode.
if [ -s "${token_source}" ]; then
  mkdir -p "${token_dir}"
  cp "${token_source}" "${token_target}"
  chmod 0744 "${token_target}"
fi

# Optional override for installations using a legacy GRID license server.
# For NVIDIA License System (DLS/CLS), the service endpoint is carried by the
# client configuration token and the packaged FeatureType=1 config is used.
if [ -s /run/gridd.conf ]; then
  cp /run/gridd.conf /etc/nvidia/gridd.conf
  chmod 0644 /etc/nvidia/gridd.conf
fi

if [ ! -s /etc/nvidia/gridd.conf ]; then
  echo "Missing /etc/nvidia/gridd.conf" >&2
  exit 1
fi
if [ ! -s "${token_target}" ] && [ ! -s /run/gridd.conf ]; then
  echo "Missing NVIDIA client configuration token. Supply /run/nvidia-client-token.tok with ExtensionServiceConfig." >&2
  exit 1
fi

mkdir -p /var/run
rm -f /var/run/nvidia-gridd /var/run/nvidia-gridd.pid

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
    if [ -s "${pidfile}" ]; then
      pid="$(cat "${pidfile}")"
      break 2
    fi
  done
  attempt=$((attempt + 1))
  sleep 1
done

case "${pid}" in
  ''|*[!0-9]*)
    echo "nvidia-gridd did not remain in the foreground and no valid PID file appeared" >&2
    exit 1
    ;;
esac

while kill -0 "${pid}" 2>/dev/null; do
  sleep 5
done

echo "nvidia-gridd process ${pid} exited" >&2
exit 1
