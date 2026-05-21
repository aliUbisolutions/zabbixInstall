#!/usr/bin/env bash
# Collects TCP connection data for Zabbix Agent 2 UserParameters.
#
# Usage:
#   connections.sh [--container <name>] discover  in|out
#   connections.sh [--container <name>] count     in|out  <ip>
#   connections.sh [--container <name>] ports     in|out  <ip>
#   connections.sh [--container <name>] states    in|out  <ip>
#
# --container  inspect connections inside a Docker container's network namespace
#              (requires: zabbix in docker group + sudo nsenter in sudoers)
#
# Direction:
#   in  — remote IPs connecting TO this host/container   (local port is a service port)
#   out — remote IPs this host/container connects TO     (local port is ephemeral)

set -euo pipefail

# ─── Input validation ─────────────────────────────────────────────────────────
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

validate_container() {
  if [[ ! "${1:-}" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    echo "ERROR: invalid container name '${1:-}'" >&2; exit 1
  fi
}

# ─── Optional --container flag ────────────────────────────────────────────────
CONTAINER=""
if [[ "${1:-}" == "--container" ]]; then
  CONTAINER="${2:?--container requires a name}"
  validate_container "$CONTAINER"
  shift 2
fi

# ─── ss wrapper — runs on host or inside a container network namespace ────────
ss_tn() {
  if [[ -n "$CONTAINER" ]]; then
    local pid
    pid=$(docker inspect -f '{{.State.Pid}}' "$CONTAINER" 2>/dev/null) \
      || { echo "ERROR: container '$CONTAINER' not found" >&2; exit 1; }
    [[ "$pid" == "0" || -z "$pid" ]] \
      && { echo "ERROR: container '$CONTAINER' is not running" >&2; exit 1; }
    sudo nsenter -t "$pid" -n -- ss -tn 2>/dev/null
  else
    ss -tn 2>/dev/null
  fi
}

# ─── Ephemeral port range ─────────────────────────────────────────────────────
_eph_low() { awk '{print $1}' /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null || echo 32768; }

# ─── Direction filter ─────────────────────────────────────────────────────────
_filter() {
  local dir="$1"
  local eph_low; eph_low=$(_eph_low)
  awk -v dir="$dir" -v eph_low="$eph_low" '
    NR>1 && NF>=5 {
      n = split($4, a, ":")
      local_port = a[n] + 0
      if (dir == "in"  && local_port <  eph_low) { print; next }
      if (dir == "out" && local_port >= eph_low) { print; next }
    }
  '
}

# ─── Extract peer IP ──────────────────────────────────────────────────────────
_peer_ips() {
  awk '{
    peer = $5
    sub(/:[0-9]+$/, "", peer)
    gsub(/[\[\]]/, "", peer)
    if (peer != "" && peer != "*") print peer
  }'
}

# ─── Commands ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  discover)
    validate_dir "${2:-}"
    mapfile -t ips < <(ss_tn | _filter "$2" | _peer_ips | sort -u)
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
    ss_tn | _filter "$2" | awk -v ip="${3}" '
      {peer=$5; sub(/:[0-9]+$/, "", peer); gsub(/[\[\]]/, "", peer); if(peer==ip) count++}
      END{print count+0}
    '
    ;;

  ports)
    validate_dir "${2:-}"; validate_ip "${3:-}"
    ss_tn | _filter "$2" | awk -v ip="${3}" -v dir="$2" '
      {peer=$5; sub(/:[0-9]+$/, "", peer); gsub(/[\[\]]/, "", peer)
       if(peer==ip){field=(dir=="in")?$4:$5; n=split(field,a,":"); print a[n]+0}}
    ' | sort -un | tr '\n' ',' | sed 's/,$//'
    ;;

  states)
    validate_dir "${2:-}"; validate_ip "${3:-}"
    ss_tn | _filter "$2" | awk -v ip="${3}" '
      {peer=$5; sub(/:[0-9]+$/, "", peer); gsub(/[\[\]]/, "", peer); if(peer==ip) print $1}
    ' | sort | uniq -c \
      | awk 'BEGIN{sep=""} {printf "%s%s=%s", sep, $2, $1; sep=","}' && echo
    ;;

  *)
    echo "Usage: $0 [--container <name>] discover in|out | count in|out <ip> | ports in|out <ip> | states in|out <ip>" >&2
    exit 1
    ;;
esac
