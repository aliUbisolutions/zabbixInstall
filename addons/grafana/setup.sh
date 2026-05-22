#!/usr/bin/env bash
# Deploys Grafana with the Zabbix datasource plugin.
# Run on the server where you want Grafana (can be the Zabbix server itself).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

command -v docker &>/dev/null      || error "Docker is required. Install it first."
command -v docker compose &>/dev/null 2>&1 \
  || docker-compose version &>/dev/null 2>&1 \
  || error "docker compose (v2) or docker-compose (v1) is required."

# ── Collect required settings ─────────────────────────────────────────────────
echo ""
echo "  Grafana + Zabbix datasource setup"
echo "  ─────────────────────────────────"
echo ""

read -rp "  Zabbix frontend URL (e.g. http://192.168.1.10/zabbix): " ZABBIX_API_URL
read -rp "  Zabbix API username [Admin]: " ZABBIX_API_USER
ZABBIX_API_USER="${ZABBIX_API_USER:-Admin}"
read -rsp "  Zabbix API password [zabbix]: " ZABBIX_API_PASSWORD
echo ""
ZABBIX_API_PASSWORD="${ZABBIX_API_PASSWORD:-zabbix}"

read -rsp "  Grafana admin password [changeme]: " GRAFANA_PASSWORD
echo ""
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-changeme}"

# ── Write .env for docker compose ─────────────────────────────────────────────
cat > "${SCRIPT_DIR}/.env" <<EOF
ZABBIX_API_URL=${ZABBIX_API_URL}
ZABBIX_API_USER=${ZABBIX_API_USER}
ZABBIX_API_PASSWORD=${ZABBIX_API_PASSWORD}
GRAFANA_USER=admin
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}
EOF
chmod 600 "${SCRIPT_DIR}/.env"

# ── Start Grafana ─────────────────────────────────────────────────────────────
info "Starting Grafana..."
cd "$SCRIPT_DIR"
if docker compose version &>/dev/null 2>&1; then
  docker compose up -d
else
  docker-compose up -d
fi

success "Grafana is running!"
echo ""
echo -e "  URL      : ${CYAN}http://$(hostname -f 2>/dev/null || hostname):3000${NC}"
echo -e "  Username : ${CYAN}admin${NC}"
echo -e "  Password : ${CYAN}${GRAFANA_PASSWORD}${NC}"
echo ""
warn "On first login: go to Apps → Zabbix → Enable the plugin before using dashboards."
