#!/usr/bin/env bash
# Deploys the TCP connection monitor add-on for Zabbix Agent 2.
# Run on each monitored host (requires root).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root (sudo)."
command -v ss &>/dev/null || error "'ss' not found. Install iproute2: dnf install iproute / apt install iproute2"

info "Installing connection monitor script..."
install -d /etc/zabbix/scripts
install -m 0755 -o root -g root "${SCRIPT_DIR}/connections.sh" /etc/zabbix/scripts/connections.sh

info "Installing UserParameter configuration..."
install -m 0644 -o root -g root "${SCRIPT_DIR}/connections.conf" /etc/zabbix/zabbix_agent2.d/connections.conf

info "Restarting zabbix-agent2..."
systemctl restart zabbix-agent2
systemctl --no-pager status zabbix-agent2 --lines=0

success "Connection monitor deployed."
echo ""
echo "Test with:"
echo "  sudo -u zabbix /etc/zabbix/scripts/connections.sh discover"
echo "  zabbix_get -s 127.0.0.1 -p 10050 -k 'connections.discover'"
