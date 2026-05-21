# TCP Connection Monitor Add-on

Adds Low-Level Discovery of all remote IPs currently connected to the monitored host, with per-IP connection count, local ports, and connection states.

## Deploy on the monitored host

```bash
git clone https://github.com/aliubisolutions/zabbixinstall
cd zabbixinstall/addons/connections
sudo bash setup.sh
```

## Configure Zabbix (web UI)

### 1 — Add a LLD rule to the host (or template)

| Field | Value |
|---|---|
| Name | TCP connections by IP |
| Type | Zabbix agent |
| Key | `connections.discover` |
| Update interval | `5m` |

### 2 — Add these Item Prototypes under the LLD rule

| Name | Key | Type | Units |
|---|---|---|---|
| Connections from {#IP} | `connections.count[{#IP}]` | Zabbix agent | `conn` |
| Ports hit by {#IP} | `connections.ports[{#IP}]` | Zabbix agent | |
| States for {#IP} | `connections.states[{#IP}]` | Zabbix agent | |

### 3 — Optional trigger prototype (alert on new/unknown IP)

Create a trigger prototype on `connections.count[{#IP}]` if you want to alert when an unexpected IP connects.

## What it collects

```
$ /etc/zabbix/scripts/connections.sh discover
{"data":[{"{#IP}":"203.0.113.5"},{"{#IP}":"198.51.100.22"}]}

$ /etc/zabbix/scripts/connections.sh count 203.0.113.5
4

$ /etc/zabbix/scripts/connections.sh ports 203.0.113.5
22,443

$ /etc/zabbix/scripts/connections.sh states 203.0.113.5
ESTAB=3,TIME-WAIT=1
```

## How it works

Uses `ss -tn` (from `iproute2`) — no external dependencies beyond what ships with any modern Linux distro.
