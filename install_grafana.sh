#!/usr/bin/env bash
# Deploys Grafana with the Zabbix datasource plugin.
# Run on the server where you want Grafana (can be the same machine as Zabbix).
# Requires Docker and Docker Compose.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAFANA_DIR="${SCRIPT_DIR}/addons/grafana"

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

usage() {
cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Deploy Grafana with the Zabbix datasource plugin via Docker.

Options:
  -z, --zabbix-url   <URL>      Zabbix frontend URL (e.g. http://192.168.1.10/zabbix)
  -u, --zabbix-user  <USER>     Zabbix API username (default: Admin)
  -p, --zabbix-pass  <PASS>     Zabbix API password
  -g, --grafana-pass <PASS>     Grafana admin password (default: changeme)
      --port         <PORT>     Grafana listen port (default: 3000)
  -h, --help                    Show this help message

Environment variables (override defaults):
  ZABBIX_API_URL, ZABBIX_API_USER, ZABBIX_API_PASSWORD, GRAFANA_PASSWORD, GRAFANA_PORT

Examples:
  sudo $(basename "$0") --zabbix-url http://zabbix.example.com/zabbix --zabbix-pass secret
  ZABBIX_API_URL=http://192.168.1.10/zabbix $(basename "$0")
EOF
  exit 0
}

# ─── Defaults ─────────────────────────────────────────────────────────────────
ZABBIX_API_URL="${ZABBIX_API_URL:-}"
ZABBIX_API_USER="${ZABBIX_API_USER:-Admin}"
ZABBIX_API_PASSWORD="${ZABBIX_API_PASSWORD:-}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-changeme}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -z|--zabbix-url)   ZABBIX_API_URL="$2";      shift 2 ;;
    -u|--zabbix-user)  ZABBIX_API_USER="$2";     shift 2 ;;
    -p|--zabbix-pass)  ZABBIX_API_PASSWORD="$2"; shift 2 ;;
    -g|--grafana-pass) GRAFANA_PASSWORD="$2";    shift 2 ;;
       --port)         GRAFANA_PORT="$2";         shift 2 ;;
    -h|--help)         usage ;;
    *) error "Unknown option: $1. Use --help for usage." ;;
  esac
done

# ─── Pre-flight checks ────────────────────────────────────────────────────────
command -v docker &>/dev/null || error "Docker is required but not installed."

COMPOSE_CMD=""
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  error "Docker Compose is required. Install the Docker Compose plugin."
fi

# ─── Prompt for missing values ────────────────────────────────────────────────
if [[ -z "$ZABBIX_API_URL" ]]; then
  read -rp "Zabbix frontend URL (e.g. http://192.168.1.10/zabbix): " ZABBIX_API_URL
fi
[[ -z "$ZABBIX_API_URL" ]] && error "Zabbix URL is required."

if [[ -z "$ZABBIX_API_PASSWORD" ]]; then
  read -rsp "Zabbix API password for '${ZABBIX_API_USER}': " ZABBIX_API_PASSWORD
  echo ""
fi
[[ -z "$ZABBIX_API_PASSWORD" ]] && error "Zabbix API password is required."

# ─── Write .env ───────────────────────────────────────────────────────────────
info "Writing configuration..."
cat > "${GRAFANA_DIR}/.env" <<EOF
ZABBIX_API_URL=${ZABBIX_API_URL}
ZABBIX_API_USER=${ZABBIX_API_USER}
ZABBIX_API_PASSWORD=${ZABBIX_API_PASSWORD}
GRAFANA_USER=admin
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}
GRAFANA_PORT=${GRAFANA_PORT}
EOF
chmod 600 "${GRAFANA_DIR}/.env"

# ─── Deploy ───────────────────────────────────────────────────────────────────
info "Starting Grafana (this may take a minute while the Zabbix plugin downloads)..."
cd "$GRAFANA_DIR"
$COMPOSE_CMD up -d

success "Grafana is running!"
echo ""
echo -e "  URL      : ${CYAN}http://$(hostname -f 2>/dev/null || hostname):${GRAFANA_PORT}${NC}"
echo -e "  Username : ${CYAN}admin${NC}"
echo -e "  Password : ${CYAN}${GRAFANA_PASSWORD}${NC}"
echo ""
warn "First login: go to Apps → Zabbix → click Enable, then open Dashboards."
