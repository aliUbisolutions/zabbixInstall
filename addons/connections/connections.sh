#!/usr/bin/env bash
# Collects TCP connection data for Zabbix Agent 2 UserParameters.
#
# Usage:
#   connections.sh discover  in|out
#   connections.sh count     in|out  <ip>
#   connections.sh ports     in|out  <ip>
#   connections.sh states    in|out  <ip>
#
# Direction:
#   in  — remote IPs connecting TO this host   (local port is a service port)
#   out — remote IPs this host connects TO     (local port is ephemeral)

set -euo pipefail

validate_ip() {
  if [[ ! "${1:-}" =~ ^[0-9a-fA-F.:]+$ ]]; then
    echo "ERROR: invalid IP '${1:-}'" >&2; exit 1
  fi
}

validate_dir() {
  if [[ "${1:-}" != "in" && "${1:-}" != "out" ]]; then
    echo "ERROR: direction must be 'in' or 'out'" >&2; exit 1
  fi
}

# Read the kernel's ephemeral port range (typically 32768–60999 on Linux).
# Local port < eph_low  → service port → this host is the server (incoming).
# Local port >= eph_low → ephemeral   → this host is the client (outgoing).
_eph_low() { awk '{print $1}' /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null || echo 32768; }

# Parse ss -tn output, filter by direction, and print matching rows.
_filter() {
  local dir="$1"
  local eph_low; eph_low=$(_eph_low)
  awk -v dir="$dir" -v eph_low="$eph_low" '
    NR>1 && NF>=5 {
      # local address is $4; port is the last colon-separated field
      n = split($4, a, ":")
      local_port = a[n] + 0
      if (dir == "in"  && local_port <  eph_low) { print; next }
      if (dir == "out" && local_port >= eph_low) { print; next }
    }
  '
}

# Extract the peer IP (strip port and IPv6 brackets) from filtered rows.
_peer_ips() {
  awk '{
    peer = $5
    sub(/:[0-9]+$/, "", peer)
    gsub(/[\[\]]/, "", peer)
    if (peer != "" && peer != "*") print peer
  }'
}

case "${1:-}" in
  discover)
    validate_dir "${2:-}"
    mapfile -t ips < <(ss -tn 2>/dev/null | _filter "$2" | _peer_ips | sort -u)
    if [[ ${#ips[@]} -eq 0 ]]; then
      echo '{"data":[]}'
    else
      sep=""; out='{"data":['
      for ip in "${ips[@]}"; do
        out+="${sep}{\"{#IP}\":\"${ip}\"}"; sep=","
      done
      echo "${out}]}"
    fi
    ;;

  count)
    validate_dir "${2:-}"; validate_ip "${3:-}"
    ss -tn dst "${3}" 2>/dev/null | _filter "$2" | wc -l | tr -d ' '
    ;;

  ports)
    validate_dir "${2:-}"; validate_ip "${3:-}"
    # For "in": show local (service) ports. For "out": show remote (destination) ports.
    ss -tn dst "${3}" 2>/dev/null | _filter "$2" \
      | awk -v dir="$2" '{
          field = (dir == "in") ? $4 : $5
          n = split(field, a, ":")
          print a[n] + 0
        }' \
      | sort -un | tr '\n' ',' | sed 's/,$//'
    ;;

  states)
    validate_dir "${2:-}"; validate_ip "${3:-}"
    ss -tn dst "${3}" 2>/dev/null | _filter "$2" \
      | awk '{print $1}' | sort | uniq -c \
      | awk 'BEGIN{sep=""} {printf "%s%s=%s", sep, $2, $1; sep=","}' && echo
    ;;

  *)
    echo "Usage: $0 discover in|out | count in|out <ip> | ports in|out <ip> | states in|out <ip>" >&2
    exit 1
    ;;
esac
