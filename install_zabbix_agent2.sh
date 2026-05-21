#!/usr/bin/env bash
# Installs and configures Zabbix Agent 2 on major Linux distributions.
# Supports: Debian/Ubuntu, RHEL/CentOS/Rocky/Alma, Amazon Linux 2/2023, SUSE/openSUSE

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
ZABBIX_VERSION="${ZABBIX_VERSION:-7.0}"
ZABBIX_SERVER="${ZABBIX_SERVER:-}"
ZABBIX_SERVER_ACTIVE="${ZABBIX_SERVER_ACTIVE:-}"
ZABBIX_HOSTNAME="${ZABBIX_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
ZABBIX_LISTEN_PORT="${ZABBIX_LISTEN_PORT:-10050}"
ZABBIX_LOG_FILE="${ZABBIX_LOG_FILE:-/var/log/zabbix/zabbix_agent2.log}"
ZABBIX_PID_FILE="${ZABBIX_PID_FILE:-/run/zabbix/zabbix_agent2.pid}"
ZABBIX_CONF="${ZABBIX_CONF:-/etc/zabbix/zabbix_agent2.conf}"

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

usage() {
cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install and configure Zabbix Agent 2 on this host.

Options:
  -s, --server      <IP/HOST>   Zabbix server address (passive checks)
  -a, --active      <IP/HOST>   Zabbix server/proxy for active checks (default: same as --server)
  -n, --hostname    <NAME>      Agent hostname reported to Zabbix (default: system hostname)
  -v, --version     <VERSION>   Zabbix major version to install (default: ${ZABBIX_VERSION})
  -p, --port        <PORT>      Agent listen port (default: ${ZABBIX_LISTEN_PORT})
  -h, --help                    Show this help message

Environment variables (override defaults):
  ZABBIX_SERVER, ZABBIX_SERVER_ACTIVE, ZABBIX_HOSTNAME,
  ZABBIX_VERSION, ZABBIX_LISTEN_PORT

Examples:
  sudo $(basename "$0") --server 192.168.1.10
  sudo $(basename "$0") --server zabbix.example.com --hostname web-server-01
  ZABBIX_VERSION=6.4 sudo $(basename "$0") --server 10.0.0.5
EOF
  exit 0
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--server)   ZABBIX_SERVER="$2";        shift 2 ;;
    -a|--active)   ZABBIX_SERVER_ACTIVE="$2"; shift 2 ;;
    -n|--hostname) ZABBIX_HOSTNAME="$2";      shift 2 ;;
    -v|--version)  ZABBIX_VERSION="$2";       shift 2 ;;
    -p|--port)     ZABBIX_LISTEN_PORT="$2";   shift 2 ;;
    -h|--help)     usage ;;
    *) error "Unknown option: $1. Use --help for usage." ;;
  esac
done

[[ -z "$ZABBIX_SERVER" ]] && error "Zabbix server address is required. Use --server <IP/HOST> or set ZABBIX_SERVER."
[[ -z "$ZABBIX_SERVER_ACTIVE" ]] && ZABBIX_SERVER_ACTIVE="$ZABBIX_SERVER"

# ─── Root check ───────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)."

# ─── OS detection ─────────────────────────────────────────────────────────────
detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID,,}"
    OS_ID_LIKE="${ID_LIKE,,:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_MAJOR="${OS_VERSION_ID%%.*}"
  else
    error "Cannot detect OS: /etc/os-release not found."
  fi
}

# ─── Package manager helpers ──────────────────────────────────────────────────
apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -q "$@"
}

rpm_install() {
  if command -v dnf &>/dev/null; then
    dnf install -y "$@"
  else
    yum install -y "$@"
  fi
}

# ─── Repository setup ─────────────────────────────────────────────────────────
install_zabbix_repo_debian() {
  local codename
  codename="$(lsb_release -sc 2>/dev/null || . /etc/os-release && echo "${VERSION_CODENAME}")"
  info "Adding Zabbix ${ZABBIX_VERSION} APT repository for ${codename}..."

  local pkg="zabbix-release_${ZABBIX_VERSION}-1+${codename}_all.deb"
  local url="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/debian/pool/main/z/zabbix-release/${pkg}"

  # Ubuntu uses a different path segment
  if [[ "$OS_ID" == "ubuntu" ]]; then
    pkg="zabbix-release_${ZABBIX_VERSION}-1+ubuntu${OS_VERSION_ID}_all.deb"
    url="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/${pkg}"
  fi

  local tmp; tmp="$(mktemp /tmp/zabbix-release.XXXXXX.deb)"
  wget -qO "$tmp" "$url" || curl -fsSL "$url" -o "$tmp" \
    || error "Failed to download Zabbix repository package from ${url}"
  dpkg -i "$tmp"
  rm -f "$tmp"
  apt-get update -qq
}

install_zabbix_repo_rpm() {
  local rpm_os rpm_ver
  case "$OS_ID" in
    amzn)
      if [[ "$OS_VERSION_ID" == "2023" ]]; then
        rpm_os="amazonlinux"; rpm_ver="2023"
      else
        rpm_os="amzn"; rpm_ver="2"
      fi
      ;;
    *)
      rpm_os="rhel"; rpm_ver="$OS_MAJOR"
      ;;
  esac

  # EL10+ requires Zabbix 7.4+ and uses a different repo URL structure.
  # Zabbix 7.0 and earlier have no EL10 packages.
  local MIN_EL10_VERSION="7.4"
  if [[ "$rpm_os" == "rhel" && "$rpm_ver" -ge 10 ]] 2>/dev/null; then
    if awk "BEGIN{exit !($ZABBIX_VERSION < $MIN_EL10_VERSION)}"; then
      warn "Zabbix ${ZABBIX_VERSION} has no packages for EL${rpm_ver}. Upgrading to ${MIN_EL10_VERSION} (minimum supported)."
      ZABBIX_VERSION="$MIN_EL10_VERSION"
    fi
    info "Adding Zabbix ${ZABBIX_VERSION} RPM repository (EL${rpm_ver} — new repo layout)..."
    local url="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/rhel/${rpm_ver}/noarch/zabbix-release-latest.el${rpm_ver}.noarch.rpm"
    rpm_install "$url"
    return
  fi

  info "Adding Zabbix ${ZABBIX_VERSION} RPM repository..."
  local url="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/${rpm_os}/${rpm_ver}/x86_64/zabbix-release-${ZABBIX_VERSION}-1.el${rpm_ver}.noarch.rpm"

  rpm_install "$url" || {
    # Fall back to generic EL URL on failure
    url="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/rhel/${rpm_ver}/x86_64/zabbix-release-${ZABBIX_VERSION}-1.el${rpm_ver}.noarch.rpm"
    rpm_install "$url"
  }
}

install_zabbix_repo_suse() {
  info "Adding Zabbix ${ZABBIX_VERSION} zypper repository..."
  zypper addrepo --no-gpgcheck \
    "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/sles/${OS_MAJOR}/x86_64/" \
    "zabbix" 2>/dev/null || warn "Repository may already exist, continuing..."
  zypper --non-interactive refresh
}

# ─── Agent installation ───────────────────────────────────────────────────────
install_agent() {
  case "$PKG_MANAGER" in
    apt)
      apt_install zabbix-agent2 zabbix-agent2-plugin-*  2>/dev/null || apt_install zabbix-agent2
      ;;
    rpm)
      rpm_install zabbix-agent2
      ;;
    zypper)
      zypper --non-interactive install zabbix-agent2
      ;;
  esac
  success "Zabbix Agent 2 installed."
}

# ─── Configuration ────────────────────────────────────────────────────────────
configure_agent() {
  info "Writing configuration to ${ZABBIX_CONF}..."

  # Back up existing config
  [[ -f "$ZABBIX_CONF" ]] && cp -p "$ZABBIX_CONF" "${ZABBIX_CONF}.bak.$(date +%Y%m%d%H%M%S)"

  mkdir -p "$(dirname "$ZABBIX_LOG_FILE")" "$(dirname "$ZABBIX_PID_FILE")"
  chown -R zabbix:zabbix "$(dirname "$ZABBIX_LOG_FILE")" "$(dirname "$ZABBIX_PID_FILE")" 2>/dev/null || true

  cat > "$ZABBIX_CONF" <<CONF
# Zabbix Agent 2 configuration — managed by install_zabbix_agent2.sh
PidFile=${ZABBIX_PID_FILE}
LogFile=${ZABBIX_LOG_FILE}
LogFileSize=10
Server=${ZABBIX_SERVER}
ServerActive=${ZABBIX_SERVER_ACTIVE}
Hostname=${ZABBIX_HOSTNAME}
ListenPort=${ZABBIX_LISTEN_PORT}
ControlSocket=/tmp/agent.sock
Include=/etc/zabbix/zabbix_agent2.d/*.conf
CONF

  success "Configuration written."
}

# ─── Service management ───────────────────────────────────────────────────────
enable_service() {
  info "Enabling and starting zabbix-agent2 service..."
  systemctl daemon-reload
  systemctl enable zabbix-agent2
  systemctl restart zabbix-agent2
  systemctl --no-pager status zabbix-agent2
  success "Zabbix Agent 2 is running."
}

# ─── Firewall hint ────────────────────────────────────────────────────────────
firewall_hint() {
  if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
    info "Detected firewalld. Opening port ${ZABBIX_LISTEN_PORT}/tcp..."
    firewall-cmd --permanent --add-port="${ZABBIX_LISTEN_PORT}/tcp" --quiet
    firewall-cmd --reload --quiet
    success "Firewall rule added."
  elif command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    info "Detected ufw. Opening port ${ZABBIX_LISTEN_PORT}/tcp..."
    ufw allow "${ZABBIX_LISTEN_PORT}/tcp" > /dev/null
    success "UFW rule added."
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  detect_os

  info "Detected OS: ${OS_ID} ${OS_VERSION_ID}"
  info "Zabbix version : ${ZABBIX_VERSION}"
  info "Zabbix server  : ${ZABBIX_SERVER}"
  info "Agent hostname : ${ZABBIX_HOSTNAME}"
  info "Listen port    : ${ZABBIX_LISTEN_PORT}"
  echo ""

  # Determine package manager and install repo
  case "$OS_ID" in
    ubuntu|debian|raspbian)
      PKG_MANAGER="apt"
      command -v wget curl &>/dev/null || apt_install wget curl
      install_zabbix_repo_debian
      ;;
    rhel|centos|rocky|almalinux|ol|fedora|amzn)
      PKG_MANAGER="rpm"
      install_zabbix_repo_rpm
      ;;
    sles|opensuse*|suse)
      PKG_MANAGER="zypper"
      install_zabbix_repo_suse
      ;;
    *)
      # Fallback: check ID_LIKE
      if echo "$OS_ID_LIKE" | grep -qE "debian|ubuntu"; then
        PKG_MANAGER="apt"
        install_zabbix_repo_debian
      elif echo "$OS_ID_LIKE" | grep -qE "rhel|fedora|centos"; then
        PKG_MANAGER="rpm"
        install_zabbix_repo_rpm
      else
        error "Unsupported OS: ${OS_ID}. Please open an issue or install manually."
      fi
      ;;
  esac

  install_agent
  configure_agent
  enable_service
  firewall_hint

  echo ""
  success "Zabbix Agent 2 installation complete!"
  echo -e "  Server  : ${CYAN}${ZABBIX_SERVER}${NC}"
  echo -e "  Hostname: ${CYAN}${ZABBIX_HOSTNAME}${NC}"
  echo -e "  Port    : ${CYAN}${ZABBIX_LISTEN_PORT}${NC}"
  echo -e "  Config  : ${CYAN}${ZABBIX_CONF}${NC}"
  echo -e "  Log     : ${CYAN}${ZABBIX_LOG_FILE}${NC}"
}

main
