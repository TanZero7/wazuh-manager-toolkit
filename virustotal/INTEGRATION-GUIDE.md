# VirusTotal: Manager Integration Guide

> Wazuh's official, built-in VirusTotal integration (one config block, no custom code), plus optional Active Response.

> **Install order: manager first (this guide), then endpoint, then verify**
>
> 1. **Manager side**: this guide, [section 3](#3-install-manager).
> 2. **Endpoint side** (only if you use Active Response):
>    [wazuh-endpoint-toolkit → virustotal-active-response](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/virustotal-active-response).
> 3. **Verify**: done from the endpoint, with an EICAR test file:
>    [endpoint guide, verification](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/virustotal-active-response/INTEGRATION-GUIDE.md#3-verification).

| | |
|---|---|
| **Wazuh** | 4.x manager |
| **Custom files needed** | None for alert-only: this follows Wazuh's own documentation exactly |
| **Trigger** | FIM rules 550 (modified) / 554 (added) |
| **Verified** | 11 September 2026: EICAR test, 65/67 AV engines flagged it, rule 87105 |

## 1. Overview

```
   File added/modified (FIM)  ──►  rule 550/554
              │
              ▼ Wazuh's built-in integratord module
   VirusTotal API: hash lookup for sha256_after
              │
              ▼
   rule 87103 (no records) / 87104 (0 positives) / 87105 (positives found)
              │
              ▼ optional Active Response (section 4)
   657 (remove-threat.exe fired) → 553 (file deleted) → 100092 / 100093 (outcome)
```

Wazuh ships this integration as a first-party feature: `integratord` and
`virustotal.py` are already installed with every manager. There's
nothing to build here; these scripts make the config steps repeatable and safe.

## 2. Requirements

| Requirement | Why | Check |
|---|---|---|
| Root on the manager | Editing `ossec.conf` | `sudo -v` |
| A VirusTotal API key | Wazuh calls VT's API directly | Free or paid plan |
| Internet access from the manager | API calls happen server-side | `curl -s https://www.virustotal.com` |
| FIM on the endpoints | FIM events are the trigger | [wazuh-endpoint-toolkit → fim](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/fim) |

## 3. Install (manager)

### 3.1 Alert-only integration

```bash
cd ~/wazuh-manager-toolkit/virustotal
sudo bash add-virustotal-integration.sh <YOUR_API_KEY>
```

Backs up `ossec.conf`, inserts:
```xml
<integration>
  <name>virustotal</name>
  <api_key>YOUR_API_KEY</api_key>
  <rule_id>550,554</rule_id>
  <alert_format>json</alert_format>
</integration>
```
config-tests before restarting, and refuses to run if a `virustotal`
integration block already exists (edit that one by hand instead of risking
a duplicate).

When it asks `Restart wazuh-manager now? [y/N]`, type **`y`** (the same applies to both scripts in section 4).

**Confirm it worked** (OK / FAIL). A good run prints, in order:

```
    [ OK ] No existing block -- safe to add
    [ OK ] Backed up to /var/ossec/backup/ossec.conf.<timestamp>.bak
    [ OK ] Integration block inserted
    [ OK ] config test passed
    [ OK ] wazuh-manager running
```

Any `[FAIL]` stops the script before the restart, so a bad config never goes live.
Fix what it says (the backup path is printed) and re-run.

## 4. Active Response (optional): auto-delete instead of alert-only

> ⚠️ Irreversible and automatic. Make sure alert-only behaviour is confirmed
> working first (verify from the endpoint), and that you actually want files
> deleted without a human in the loop, before wiring this up across the fleet.

```bash
# Adds the <command>/<active-response> block (fires remove-threat.exe on rule 87105)
sudo bash add-virustotal-active-response.sh

# Optional but recommended: rules 100092/100093, clear success/failure alerts
# with the file path, instead of just the generic "Active response fired" rule 657.
# Straight from Wazuh's own official VirusTotal + Active Response docs, IDs included.
sudo bash install-manager-rules.sh
```

**Confirm it worked** (OK / FAIL). `add-virustotal-active-response.sh` should print:

```
    [ OK ] VirusTotal integration present
    [ OK ] No existing block -- safe to add
    [ OK ] Backed up to /var/ossec/backup/virustotal-kit/ossec.conf.<timestamp>.bak
    [ OK ] Active Response configuration added
    [ OK ] config test passed
    [ OK ] wazuh-manager running
```

and `install-manager-rules.sh`:

```
    [ OK ] Backed up        (or: No existing file)
    [ OK ] Installed /var/ossec/etc/rules/local_rules_virustotal.xml
    [ OK ] config test passed
    [ OK ] wazuh-manager running
```

Then confirm the manager's active-response queue connected after the restart:
```bash
grep 'queue/alerts/ar' /var/ossec/logs/ossec.log | tail -3
```

> ⏳ The manager pushes the new active-response config to agents on its own cycle,
> so endpoints may take **5–10 minutes** to pick it up. That's expected.

**Next →** install the endpoint half on each PC:
[wazuh-endpoint-toolkit → virustotal-active-response](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/virustotal-active-response).
The chain only completes once `remove-threat.exe` is on the agent.

## 5. Useful manager-side checks

Once endpoints are set up and the EICAR test has been run from the endpoint:

```bash
grep -a "VirusTotal: Alert" /var/ossec/logs/alerts/alerts.json | tail -5            # 87105 positives
grep -a '"id":"657"' /var/ossec/logs/alerts/alerts.json | tail -5                     # AR fired at all
grep -a '"id":"100092"\|"id":"100093"' /var/ossec/logs/alerts/alerts.json | tail -5  # AR outcome
```

## 6. Troubleshooting (manager)

| Symptom | Cause | Fix |
|---|---|---|
| Script refuses to run, says a block already exists | A `virustotal` integration (or `remove-threat` command) is already configured | Edit `ossec.conf` by hand instead; find it with `grep -A4 virustotal ossec.conf` / `grep -A6 remove-threat ossec.conf` |
| `rule.id:87101` (error) instead of a real result | API key invalid, or rate-limited | Confirm the key works directly: `curl -s "https://www.virustotal.com/api/v3/files/<any-known-hash>" -H "x-apikey: YOUR_KEY"` |
| `ossec.log` shows `wazuh-integratord: ERROR ... Exit status was: 4` and no `87105` ever appears, even though FIM (`550`/`554`) is firing | Exit code 4 = `ERR_NO_RESPONSE_VT` in the shipped `virustotal.py`: usually the API key itself is being rejected, not a connectivity problem | Test the key directly against VirusTotal, using a hash you already have from a Wazuh FIM alert: `curl -H "x-apikey: YOUR_KEY" "https://www.virustotal.com/api/v3/files/<sha256>"`. A `{"error":{"code":"WrongCredentialsError"}}` response means the key itself is wrong/revoked, not a config bug |
| `ossec.log` shows `Enabling integration for: 'virustotal'` appearing **twice**, and `grep -c '<name>virustotal</name>' ossec.conf` returns 2 | A hand-rolled repair script used Python's `str.replace()` on `</ossec_config>` with no count limit: `ossec.conf` can legally contain more than one `<ossec_config>` root section, and an unbounded replace inserts into every one of them | Remove all VirusTotal `<integration>` blocks, then re-insert exactly **one**. The scripts here do a single, bounded insert before the last `</ossec_config>`; this only bites custom/manual repair scripts |
| 657 fires but no 553 / 100092 | `remove-threat.exe` missing on that agent | Install the endpoint half: [virustotal-active-response](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/virustotal-active-response) |
| Endpoint-side problems (no alert after EICAR, Defender ate the file) | — | See the [endpoint guide's troubleshooting](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/virustotal-active-response/INTEGRATION-GUIDE.md#4-troubleshooting) |
