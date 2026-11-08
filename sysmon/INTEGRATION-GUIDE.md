# Sysmon: Manager Integration Guide

> Confirms the manager has Wazuh's built-in Sysmon ruleset (~150 rules), and shows how to push the Sysmon channel to many agents centrally.

> **Install order: manager first (this guide), then endpoint, then verify**
>
> 1. **Manager side**: this guide. A quick check, nothing to install.
> 2. **Endpoint side**: [wazuh-endpoint-toolkit → sysmon](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/sysmon).
> 3. **Verify**: done from the endpoint, [endpoint guide § 4](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/sysmon/INTEGRATION-GUIDE.md#4-verification).

## 1. Check the built-in ruleset

Nothing to *install*: the Sysmon ruleset (event IDs 1, 3, 7, 8, 10, 11, 13, 20;
~150 rules) ships with every Wazuh manager. This script confirms that's true on
your install rather than assuming it.

```bash
cd ~/wazuh-manager-toolkit/sysmon
sudo bash check-sysmon-rules.sh
```

**Confirm it worked** (OK / FAIL). A healthy manager prints:

```
==> Sysmon rule files (built-in)
    [ OK ] all 10 expected Sysmon rule files present
==> Rule count sanity check
    [ OK ] <N> rule definitions counted in the core Sysmon files
==> wazuh-analysisd running
    [ OK ] wazuh-analysisd is running
```

| Result | Meaning |
|---|---|
| **OK** on every line | Manager ready. Continue to the endpoint side |
| **WARN** "x/10 expected files found" | Different Wazuh version or a customized ruleset. Usually fine, so continue, but if no `sysmon_event*` alerts show up during endpoint verification, review the ruleset |
| **WARN** "none of the expected filenames found" then **OK** "found … by content" | Renamed files in a newer Wazuh version; coverage is still there, so continue |
| **FAIL** "no Sysmon rule coverage found at all" | Ruleset missing/customized; restore Wazuh's default ruleset first |
| **FAIL** on `wazuh-analysisd` | Manager not running: `sudo systemctl restart wazuh-manager`, wait a minute, re-run |

**Next →** [wazuh-endpoint-toolkit → sysmon](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/sysmon)

## 2. Optional: push the Sysmon channel centrally

The endpoint script adds the Sysmon `<localfile>` to each agent's local
`ossec.conf`. For many machines, push it from the agent group's shared config
instead:

```bash
sudo nano /var/ossec/etc/shared/default/agent.conf
```

```xml
<agent_config os="Windows">
  <localfile>
    <location>Microsoft-Windows-Sysmon/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>
</agent_config>
```

Validate with `sudo /var/ossec/bin/verify-agent-conf`. Agents receive it on the
manager's push cycle (allow **5–10 minutes**). Sysmon itself still has to be
installed on each endpoint.

## 3. Troubleshooting (manager)

| Symptom | Cause | Fix |
|---|---|---|
| Endpoint operational log has events but nothing reaches the dashboard | Ruleset missing on the manager, or the endpoint isn't wired | Re-run `check-sysmon-rules.sh`; then check the [endpoint troubleshooting](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/sysmon/INTEGRATION-GUIDE.md#7-troubleshooting) |
