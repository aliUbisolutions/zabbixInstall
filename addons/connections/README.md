# TCP Connection Monitor Add-on

Monitors two directions of TCP connections on any host running Zabbix Agent 2:

| Direction | What it shows |
|---|---|
| **in** | Remote IPs connecting **to** this host (e.g. web clients, SSH sessions) |
| **out** | Remote IPs this host connects **to** (e.g. databases, APIs, other services) |

Each direction gets its own LLD rule, so Zabbix auto-creates one item per IP for connection count, ports, and states.

## Deploy on the monitored host

```bash
git clone https://github.com/aliubisolutions/zabbixinstall
cd zabbixinstall/addons/connections
sudo bash setup.sh
```

## Configure Zabbix (web UI)

Do the following **twice** — once for **incoming**, once for **outgoing**.

### Step 1 — Add a Discovery Rule

Go to **Data collection → Hosts** → your host → **Discovery rules** → **Create discovery rule**

| | Incoming | Outgoing |
|---|---|---|
| **Name** | `TCP incoming connections` | `TCP outgoing connections` |
| **Type** | Zabbix agent | Zabbix agent |
| **Key** | `connections.in.discover` | `connections.out.discover` |
| **Update interval** | `5m` | `5m` |

### Step 2 — Add Item Prototypes (under each discovery rule)

**Incoming rule** item prototypes:

| Name | Key | Info type |
|---|---|---|
| `Incoming connections from {#IP}` | `connections.in.count[{#IP}]` | Numeric (unsigned) |
| `Incoming ports from {#IP}` | `connections.in.ports[{#IP}]` | Text |
| `Incoming states from {#IP}` | `connections.in.states[{#IP}]` | Text |

**Outgoing rule** item prototypes:

| Name | Key | Info type |
|---|---|---|
| `Outgoing connections to {#IP}` | `connections.out.count[{#IP}]` | Numeric (unsigned) |
| `Outgoing ports to {#IP}` | `connections.out.ports[{#IP}]` | Text |
| `Outgoing states to {#IP}` | `connections.out.states[{#IP}]` | Text |

## Test from the command line

```bash
# See which IPs are connecting in
sudo -u zabbix /etc/zabbix/scripts/connections.sh discover in

# See which IPs this host connects out to
sudo -u zabbix /etc/zabbix/scripts/connections.sh discover out

# Detail for a specific IP
sudo -u zabbix /etc/zabbix/scripts/connections.sh count in 203.0.113.5
sudo -u zabbix /etc/zabbix/scripts/connections.sh ports out 10.0.0.1
sudo -u zabbix /etc/zabbix/scripts/connections.sh states in 203.0.113.5
```

## How direction is determined

Uses the kernel's ephemeral port range (`/proc/sys/net/ipv4/ip_local_port_range`, typically 32768–60999):
- Local port **below** range → this host is the **server** → **incoming**
- Local port **within** range → this host is the **client** → **outgoing**
