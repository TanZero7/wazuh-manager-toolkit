# FIM: Manager Integration Guide

> Confirms the manager has Wazuh's built-in FIM alerting rules, and shows how to push the FIM scope to many agents centrally.

> **Install order: manager first (this guide), then endpoint, then verify**
>
> 1. **Manager side**: this guide. A quick check, nothing to install.
> 2. **Endpoint side**: [wazuh-endpoint-toolkit → fim](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/fim).
> 3. **Verify**: done from the endpoint, [endpoint guide § 3](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/fim/INTEGRATION-GUIDE.md#3-verification).

## 1. Check the built-in rules

There is nothing to *install*: rules 550 (modified), 553 (deleted) and 554
(added), plus the rest of the FIM alerting path, ship with every Wazuh manager.
This script confirms that's actually true on your install (a stripped-down or
heavily customized ruleset is the only case where it wouldn't be).

```bash
cd ~/wazuh-manager-toolkit/fim
sudo bash check-fim-rules.sh
```

**Confirm it worked** (OK / FAIL). A healthy manager prints:

```
==> Built-in FIM rule file
    [ OK ] found in <rules file>.xml
==> The three core FIM rules
    [ OK ] rule 550 present
    [ OK ] rule 553 present
    [ OK ] rule 554 present
==> ossec.conf loads the default ruleset
    [ OK ] ruleset/rules is loaded
==> wazuh-analysisd running
    [ OK ] wazuh-analysisd is running
```

| Result | Meaning |
|---|---|
| **OK** on every line | Manager ready. Continue to the endpoint side |
| **FAIL** on a rule or ruleset line | Customized/stripped ruleset; restore Wazuh's default ruleset before continuing |
| **FAIL** on `wazuh-analysisd` | Manager not running: `sudo systemctl restart wazuh-manager`, wait a minute, re-run |

**Next →** [wazuh-endpoint-toolkit → fim](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/fim)

## 2. Optional: push the FIM scope centrally

The endpoint script edits each agent's local `ossec.conf`, which suits a single
machine or a first test. For many machines, put the same scope in the agent
group's shared config on the manager instead (one place, pushed automatically
to every agent in the group):

```bash
sudo nano /var/ossec/etc/shared/default/agent.conf
```

```xml
<agent_config os="Windows">
  <syscheck>
    <directories check_all="yes" realtime="yes">C:\Users\*\Desktop</directories>
    <directories check_all="yes" realtime="yes">C:\Users\*\Downloads</directories>
    <alert_new_files>yes</alert_new_files>
    <ignore type="sregex">\.tmp$|\.temp$|\.crdownload$|\.part$|\.partial$|\.~lock|desktop\.ini$|thumbs\.db$</ignore>
  </syscheck>
</agent_config>
```

Validate with `sudo /var/ossec/bin/verify-agent-conf` before agents pick it up.
Agents receive it on the manager's push cycle (allow **5–10 minutes**).

> The no-event-loss setting (`<client_buffer>`) can **not** be pushed this way:
> it only works in each agent's local `ossec.conf`. Keep running
> `set-no-event-loss.ps1` on the endpoints.

## 3. Troubleshooting (manager)

| Symptom | Cause | Fix |
|---|---|---|
| Endpoint `ossec.log` shows FIM events but no alerts in the dashboard | Rules missing/customized on the manager | Re-run `check-fim-rules.sh`, fix any `[FAIL]` |
| Group config not reaching agents | Invalid `agent.conf` or agent not in that group | `verify-agent-conf`; check the agent's group with `/var/ossec/bin/agent_groups -l` |
