# Zabbix Agent 2 Installer

A single-script installer for **Zabbix Agent 2** that automatically detects the Linux distribution and configures everything needed to connect to your Zabbix server.

## Supported Distributions

| Family | Distributions |
|---|---|
| Debian/Ubuntu | Ubuntu 20.04/22.04/24.04, Debian 10/11/12 |
| RHEL-based | RHEL 7/8/9, CentOS 7/8, Rocky Linux 8/9, AlmaLinux 8/9, Oracle Linux |
| Amazon Linux | Amazon Linux 2, Amazon Linux 2023 |
| SUSE | SLES 15, openSUSE Leap 15 |

## Quick Start

```bash
sudo bash install_zabbix_agent2.sh --server <ZABBIX_SERVER_IP>
```

## Options

| Flag | Description | Default |
|---|---|---|
| `-s`, `--server` | Zabbix server address (passive checks) | **required** |
| `-a`, `--active` | Server/proxy for active checks | same as `--server` |
| `-n`, `--hostname` | Agent hostname reported to Zabbix | system hostname |
| `-v`, `--version` | Zabbix major version (`6.4`, `7.0`, `7.2`) | `7.0` |
| `-p`, `--port` | Agent listen port | `10050` |
| `-h`, `--help` | Show help | |

All options can also be set via environment variables: `ZABBIX_SERVER`, `ZABBIX_SERVER_ACTIVE`, `ZABBIX_HOSTNAME`, `ZABBIX_VERSION`, `ZABBIX_LISTEN_PORT`.

## Examples

```bash
# Minimal — passive checks only
sudo bash install_zabbix_agent2.sh --server 192.168.1.10

# Custom hostname and active checks to a proxy
sudo bash install_zabbix_agent2.sh \
  --server zabbix.example.com \
  --active proxy.example.com \
  --hostname web-server-01

# Install Zabbix 6.4 LTS instead of 7.0
sudo bash install_zabbix_agent2.sh --server 10.0.0.5 --version 6.4

# Using environment variables (useful in cloud-init / Ansible)
ZABBIX_SERVER=10.0.0.5 ZABBIX_VERSION=7.0 sudo -E bash install_zabbix_agent2.sh
```

## What the Script Does

1. Detects the OS distribution and version
2. Adds the official Zabbix repository for that distro
3. Installs `zabbix-agent2`
4. Writes `/etc/zabbix/zabbix_agent2.conf` (backs up any existing config)
5. Enables and starts the `zabbix-agent2` systemd service
6. Opens the listen port in `firewalld` or `ufw` if either is active

## Configuration File

The generated config is written to `/etc/zabbix/zabbix_agent2.conf`. You can further customise it or drop additional `.conf` files into `/etc/zabbix/zabbix_agent2.d/`.

## Uninstall

```bash
# Debian/Ubuntu
sudo apt-get remove --purge zabbix-agent2

# RHEL / Amazon Linux
sudo dnf remove zabbix-agent2   # or yum

# SUSE
sudo zypper remove zabbix-agent2
```
