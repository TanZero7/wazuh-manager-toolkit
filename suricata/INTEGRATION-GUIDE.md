# Suricata: Manager Integration Guide

> Custom rules (100200–100232) that turn Suricata's DNS, TLS and HTTP events into visible, searchable alerts. **Required** for the Suricata endpoint IDS to be useful.

> **Install order: manager first (this guide), then endpoint, then verify**
>
> 1. **Manager side**: this guide, [section 2](#2-install-the-rules).
> 2. **Endpoint side**: [wazuh-endpoint-toolkit → suricata](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/suricata).
> 3. **Verify**: done from the endpoint, [endpoint guide § 5](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/suricata/INTEGRATION-GUIDE.md#5-verification).

| | |
|---|---|
| **Manager** | Ubuntu 22.04+ with Wazuh manager, indexer, dashboard (4.14.7 tested) |
| **Files** | `local_rules_suricata.xml`, `install-manager-rules.sh` |

## 1. Requirements

- Wazuh manager 4.x running, with `wazuh-analysisd` and `wazuh-remoted` active.
- Root access, to install the custom rules file and restart the manager.
- TCP **1514** (agent events) and **1515** (enrollment) reachable from the endpoints.

> ⚠️ **Give the manager a static address**
>
> Agents connect to the manager by IP. If its address changes, every agent silently stops reporting until reconfigured. Use a static IP or a DHCP reservation. During this deployment the manager's DHCP lease changed three times and each change broke the agent link until re-pointed.

### Version compatibility

Wazuh requires **manager version ≥ agent version**. A manager refuses an agent newer than itself, and the agent will appear enrolled but never report. The installer below prints the manager version; note it down, because the Windows agent you install on endpoints must be **no newer** than it. You can also check any time with:

```bash
sudo /var/ossec/bin/wazuh-control info
```

## 2. Install the rules

```bash
cd ~/wazuh-manager-toolkit/suricata
sudo bash install-manager-rules.sh
```

The script reports the manager version, checks the built-in Suricata ruleset is present, backs up any existing copy, installs `/var/ossec/etc/rules/local_rules_suricata.xml`, validates with `wazuh-logtest` **before** restarting, then restarts the manager and confirms it came back.

> ⚠️ **Validation runs before the restart on purpose.** A malformed rules file prevents wazuh-manager from starting at all. Validating first means a bad file is caught while the manager is still up.

**Confirm it worked** (OK / FAIL). A good run includes:

```
==> Manager identity and version
    [ OK ] Manager version: 4.x.x
    [ OK ] wazuh-analysisd is running
==> Confirm the built-in Suricata ruleset is present
    [ OK ] Found 0475-suricata_rules.xml
==> Install rules
    [ OK ] Installed /var/ossec/etc/rules/local_rules_suricata.xml
```

When it asks `Restart wazuh-manager now? [y/N]`, type **`y`**. It should end with:

```
==> Restart wazuh-manager
    [ OK ] wazuh-manager is running
```

| Result | Meaning |
|---|---|
| **OK** on the lines above and the manager restarts | Manager side done |
| **WARN** "Sample … missing, skipping" during validation | Expected: the `logtest-samples/` events aren't part of this release, so pre-restart validation is skipped. The rules are still checked when the manager loads them, and you verify end to end from the endpoint |
| **WARN** "No built-in Suricata ruleset found" | The custom rules chain onto built-in rules 86601–86604 and won't load without them; restore Wazuh's default ruleset first |
| **FAIL** / manager doesn't come back up | Remove `/var/ossec/etc/rules/local_rules_suricata.xml` (or restore the backup it printed), restart, and check `ossec.log` |

> ⏳ After the restart, give it **5–10 minutes** before judging anything from the endpoint side.

**Next →** [wazuh-endpoint-toolkit → suricata](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/suricata)

## 3. How the rules work

### 3.1 Why the custom rules are required

Wazuh's built-in Suricata ruleset (`0475-suricata_rules.xml`) contains exactly five rules:

| Rule | Level | Matches | Reaches dashboard? |
|---|---|---|---|
| 86600 | 0 | any decoded eve event | no |
| 86601 | 3 | event_type: alert | yes |
| 86602 | 0 | event_type: http | NO |
| 86603 | 0 | event_type: dns | NO |
| 86604 | 0 | event_type: tls | NO |

In Wazuh, **level 0 means decode then discard**. The custom ruleset chains child rules onto those level-0 parents and re-grades them to level 3 so the events survive:

```xml
<rule id="100220" level="3">
  <if_sid>86604</if_sid>                    <!-- parent: event_type tls -->
  <field name="tls.sni">\.+</field>          <!-- presence check, see below -->
  <description>Suricata: TLS connection to $(tls.sni) by $(src_ip)</description>
  <group>suricata_tls,network_visibility,tls,</group>
</rule>
```

> ⚠️ **Two traps when writing your own rules**
>
> \.+ is NOT "one or more dots". Wazuh's <field> uses OS_Regex by default, where \. means any character, so this is the idiomatic "field exists" test. And sibling rules under one <if_sid> are NOT evaluated in file order -- a catch-all sibling will shadow a specific one. Use negate="yes" to make them mutually exclusive rather than order-dependent.


### 3.2 Rules installed

| Rule | Level | Fires on |
|---|---|---|
| 100200 | 12 | High-severity signature (alert.severity 1) |
| 100201 | 7 | Medium-severity signature (alert.severity 2) |
| 100202 | 4 | Low-severity signature (alert.severity 3) |
| 100205 | 10 | 8+ alerts from one source in 60s (scan) |
| 100210 | 3 | DNS query — visibility |
| 100211 | 8 | DNS tunnelling: abnormally long label |
| 100212 | 5 | Frequently abused TLD |
| 100220 | 3 | TLS SNI — visibility |
| 100221 | 4 | TLS with no SNI |
| 100230 | 3 | HTTP request — visibility |
| 100231 | 7 | Executable or archive over cleartext HTTP |
| 100232 | 6 | Scripted HTTP client (curl, PowerShell, BITS) |

## 4. Command-line views (on the manager)

```bash
# live tail of Suricata alerts
tail -f /var/ossec/logs/alerts/alerts.json | grep --line-buffered '"suricata"'

# which custom rules have fired
grep -o '"id":"1002[0-9][0-9]"' /var/ossec/logs/alerts/alerts.json | sort | uniq -c | sort -rn

# agent connectivity
sudo /var/ossec/bin/agent_control -l
```

## 5. Tuning noise (manager side)

Endpoint-side suppression (`threshold.config`) is the first lever; see the [endpoint guide](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/suricata/INTEGRATION-GUIDE.md#7-operations). On the manager:

1. Add `<options>no_full_log</options>` to rules 100210/100220. Keeps the indexed fields, drops the raw event.
2. Drop the visibility rules to level 2 so they're counted but not alerted, then raise only what you need.

Re-run `install-manager-rules.sh` after editing so the change is validated and applied.

## 6. Uninstall

```bash
sudo rm /var/ossec/etc/rules/local_rules_suricata.xml
sudo systemctl restart wazuh-manager
```

## 7. Troubleshooting (manager)

| Symptom | Cause | Fix |
|---|---|---|
| Signature alerts appear but no DNS/TLS/HTTP | Custom rules not installed; built-in 86602-86604 are level 0 (decode then discard) | Run section 2 |
| Agents stopped reporting after a network change | Manager IP changed (DHCP) | Give the manager a static IP; update `<address>` in each agent's `ossec.conf` |
| `wazuh-logtest` reports 0/N when rules are fine | `-q` suppresses all output including the Phase 3 result | Use `-v` alone, never `-q -v` |
| Endpoint-side problems | — | See the [endpoint troubleshooting](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/suricata/INTEGRATION-GUIDE.md#8-troubleshooting) |

### Manager VM will not get an IPv4 address

Seen on a bridged VMware guest. Symptoms and how to tell them apart:

- **NetworkManager reports "connection profile failed"** and the interface has only an fe80:: address. Note that Ubuntu's network indicator can show "connected" on IPv6 alone, so the icon does not prove IPv4 works.
- **If DHCP times out but the gateway is pingable after setting a static address**, layer 2 bridging is fine and the DHCP server is not answering. Assign a static IP.
- **If the gateway is not pingable even with a static address**, the bridge itself is not carrying frames. Check that VMware Bridge Protocol is enabled on the correct physical adapter, and that VMnet0 is not auto-bridged to a disconnected NIC.

```
# inside the guest -- distinguish the two cases
ip -br a show ens33
journalctl -u NetworkManager -b | grep -iE 'dhcp4|Activation'
ping -c3 <gateway>
```


