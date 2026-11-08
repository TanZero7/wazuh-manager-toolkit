# YARA: Manager Integration Guide

> Installs rules 100700 (match) / 100701 (clean) and the active-response block that tells agents to YARA-scan every file FIM sees added or changed.

> **Install order: manager first (this guide), then endpoint, then verify**
>
> 1. **Manager side**: this guide, sections 1–2.
> 2. **Endpoint side**: [wazuh-endpoint-toolkit → yara](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/yara).
> 3. **Verify**: done from the endpoint, including a live marker-file test:
>    [endpoint guide § 4](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/yara/INTEGRATION-GUIDE.md#4-verification).
>
> Doing this side first means the endpoint's "Manager has pushed yara-scan into
> ar.conf" check can pass on its first run.

| | |
|---|---|
| **Wazuh** | 4.x manager |
| **Files** | `local_rules_yara.xml`, `install-manager-rules.sh`, `active-response-block.xml`, `logtest-samples/` |
| **Trigger** | FIM rules 550 (modified) / 554 (added) → active-response `yara-scan` on the same agent |

## 1. Install the rules

```bash
cd ~/wazuh-manager-toolkit/yara
sudo bash install-manager-rules.sh
```

Backs up any existing copy, installs `/var/ossec/etc/rules/local_rules_yara.xml`,
and validates both rules with `wazuh-logtest` against the sample events in
`logtest-samples/`. It does **not** restart the manager; that happens in section 2.

**Confirm it worked** (OK / FAIL). A good run includes:

```
==> Install rules
    [ OK ] Installed /var/ossec/etc/rules/local_rules_yara.xml
==> Validate rules with wazuh-logtest (before restarting)
    [ OK ] yara-match.json -> rule 100700 (as expected)
    [ OK ] yara-clean.json -> rule 100701 (as expected)
    [ OK ] All 2/2 rule validations passed
```

| Result | Meaning |
|---|---|
| **OK** `All 2/2 rule validations passed` | Rules are correct; go to section 2 |
| **FAIL** `yara-match.json -> expected 100700, got …` | The match rule's pattern is wrong; see the note below. Don't continue until this passes |

> **Why 100700 uses `\.+`:** Wazuh's `<field>` uses OS_Regex by default, where
> `\.` means *any character* and a bare `.` is a *literal dot*. So `\.+` is the
> idiom for "field has a value". An earlier "fix" changed it to `.+`, which only
> matches a value made of dots; YARA rule names can't contain dots, so 100700
> could never fire. The logtest check above catches exactly this.

## 2. Wire the active-response block (manual step)

This one edit is done by hand on purpose: it touches the manager's main
`ossec.conf`, which every other integration also depends on, so an automated
merge that gets it wrong could take the whole manager down. (Same reason Wazuh's
own docs ask for this step manually.)

1. Open the config:
   ```bash
   sudo nano /var/ossec/etc/ossec.conf
   ```
2. Inside `<ossec_config>`, near the other `<command>` definitions, paste the
   contents of `active-response-block.xml`:
   ```xml
   <command>
     <name>yara-scan</name>
     <executable>yara-scan.cmd</executable>
     <timeout_allowed>no</timeout_allowed>
   </command>
   <active-response>
     <disabled>no</disabled>
     <command>yara-scan</command>
     <location>local</location>
     <rules_id>550,554</rules_id>
   </active-response>
   ```
3. Save (`Ctrl+O`, `Enter`, `Ctrl+X`), then **test before restarting**:
   ```bash
   sudo /var/ossec/bin/wazuh-analysisd -t
   sudo systemctl restart wazuh-manager
   ```

**Confirm it worked** (OK / FAIL):

| Result | Meaning |
|---|---|
| **OK**: `wazuh-analysisd -t` reports the configuration is OK, and `sudo systemctl is-active wazuh-manager` prints `active` | Manager side done |
| **FAIL**: `wazuh-analysisd -t` reports an error | Don't restart. Fix the pasted block (usually a missing tag or pasting outside `<ossec_config>`) and test again |

> ⏳ Agents receive the new active-response config (`ar.conf`) on the manager's
> own push cycle, so allow **5–10 minutes** before the endpoint check passes.

**Next →** [wazuh-endpoint-toolkit → yara](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/yara)

## 3. Troubleshooting (manager)

| Symptom | Cause | Fix |
|---|---|---|
| Endpoint `yara-results.log` has `"match"` lines but no 100700 alert | Rule 100700's pattern isn't `\.+` (see section 1 note) | Re-run `install-manager-rules.sh` from this repo and confirm `[ OK ] yara-match.json -> rule 100700` |
| Endpoint check "Manager has pushed yara-scan into ar.conf" keeps failing | Active-response block not pasted, manager not restarted, or push cycle not reached yet | Confirm `grep -A3 yara-scan /var/ossec/etc/ossec.conf`, restart, wait 5–10 minutes |
| Manager won't start after the edit | Malformed block in `ossec.conf` | Fix the block; always run `wazuh-analysisd -t` before restarting |
| Endpoint-side problems (stuck scans, nothing firing) | — | See the [endpoint gotchas](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/yara/INTEGRATION-GUIDE.md#6-windows-specific-gotchas-found-and-fixed-during-this-build) |
