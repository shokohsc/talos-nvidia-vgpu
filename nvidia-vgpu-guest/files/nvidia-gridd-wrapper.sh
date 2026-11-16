#!/bin/sh
set -eu

token_dir=/etc/nvidia/ClientConfigToken
token_target="${token_dir}/client_configuration_token.tok"
dls_url="${NVIDIA_DLS_URL:-https://dls.home.arpa}"

# A legacy GRID configuration bypasses FastAPI-DLS entirely. Otherwise fetch
# a fresh NVIDIA License System token before starting the licensing daemon.
if [ -s /run/gridd.conf ]; then
  cp /run/gridd.conf /etc/nvidia/gridd.conf
  chmod 0644 /etc/nvidia/gridd.conf
else
  mkdir -p "${token_dir}"
  /usr/local/bin/nvidia-dls-token-fetcher \
    --url "${dls_url}" \
    --output "${token_target}"
  chmod 0744 "${token_target}"
fi

if [ ! -s /etc/nvidia/gridd.conf ]; then
  echo "Missing /etc/nvidia/gridd.conf" >&2
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
