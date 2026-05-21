#!/usr/bin/env bash
# Collects TCP connection data for Zabbix Agent 2 UserParameters.
# Usage: connections.sh discover | count <ip> | ports <ip> | states <ip>

set -euo pipefail

# Validate that the argument looks like an IP address (prevents command injection)
validate_ip() {
  if [[ ! "${1:-}" =~ ^[0-9a-fA-F.:]+$ ]]; then
    echo "ERROR: invalid IP '${1:-}'" >&2
    exit 1
  fi
}

# Extract the remote (peer) IP from ss output, stripping the port suffix.
# Handles IPv4 (1.2.3.4:port) and IPv6 ([::1]:port).
_parse_remote_ips() {
  awk 'NR>1 && NF>=5 {
    peer = $5
    sub(/:[0-9]+$/, "", peer)   # strip :port
    gsub(/[\[\]]/, "", peer)    # strip IPv6 brackets
    if (peer != "" && peer != "*") print peer
  }'
}

case "${1:-}" in
  discover)
    mapfile -t ips < <(ss -tn 2>/dev/null | _parse_remote_ips | sort -u)
    if [[ ${#ips[@]} -eq 0 ]]; then
      echo '{"data":[]}'
    else
      sep=""
      out='{"data":['
      for ip in "${ips[@]}"; do
        out+="${sep}{\"{#IP}\":\"${ip}\"}"
        sep=","
      done
      out+="]}"
      echo "$out"
    fi
    ;;

  count)
    validate_ip "${2:-}"
    ss -tn dst "${2}" 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' '
    ;;

  ports)
    validate_ip "${2:-}"
    # Return comma-separated sorted unique local ports (the services being hit)
    ss -tn dst "${2}" 2>/dev/null \
      | awk 'NR>1 && NF>=5 {print $4}' \
      | awk -F: '{print $NF}' \
      | sort -un \
      | tr '\n' ',' \
      | sed 's/,$//'
    ;;

  states)
    validate_ip "${2:-}"
    # Return state=count pairs, e.g. "ESTAB=3,TIME-WAIT=1"
    ss -tn dst "${2}" 2>/dev/null \
      | awk 'NR>1 {print $1}' \
      | sort \
      | uniq -c \
      | awk 'BEGIN{sep=""} {printf "%s%s=%s", sep, $2, $1; sep=","}'
    echo
    ;;

  *)
    echo "Usage: $0 discover | count <ip> | ports <ip> | states <ip>" >&2
    exit 1
    ;;
esac
