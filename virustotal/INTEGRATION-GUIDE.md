# VirusTotal — Integration Guide

> Wazuh's official, built-in VirusTotal integration — one config block, no custom code.

| | |
|---|---|
| **Wazuh** | 4.x manager |
| **Custom files needed** | None — this follows Wazuh's own documentation exactly |
| **Trigger** | FIM rules 550 (modified) / 554 (added) |
| **Verified** | 11 September 2026 — EICAR test, 65/67 AV engines flagged it, rule 87105 |

## 1. Overview

```
   File added/modified (FIM)  ──►  rule 550/554
              │
              ▼ Wazuh's built-in integratord module
   VirusTotal API: hash lookup for sha256_after
              │
              ▼
   rule 87103 (no records) / 87104 (0 positives) / 87105 (positives found)
```

Wazuh ships this integration as a first-party feature — `integratord` and
`virustotal.py` are already installed with every manager. There's genuinely
nothing to build here; this kit exists purely to make the one required
config step repeatable and safe.

## 2. Requirements

| Requirement | Why | Check |
|---|---|---|
| Root on the manager | Editing `ossec.conf` | — |
| A VirusTotal API key | Wazuh calls VT's API directly | Free or paid plan |
| Internet access from the manager | API calls happen server-side | `curl -s https://www.virustotal.com` |
| FIM enabled on at least one agent | This is what generates the trigger event | see `fim/` in [wazuh-endpoint-toolkit](https://github.com/TanZero7/wazuh-endpoint-toolkit) |

## 3. Install

```bash
cd wazuh-manager-toolkit/virustotal
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

## 4. Verification

### Fire-test with EICAR

EICAR is a standard, industry-wide benign test string every AV engine
recognizes as "this is a test," not real malware — safe to use.

1. On the endpoint, temporarily exclude a throwaway test folder from
   Defender (it will otherwise quarantine the file before FIM/VirusTotal
   ever see it):
   ```powershell
   $t = "$env:USERPROFILE\Downloads\vt_test"; New-Item -ItemType Directory -Force $t
   Add-MpPreference -ExclusionPath $t
   ```
2. Write the EICAR test string to a file in that folder (get the exact
   string from https://www.eicar.org/download-anti-malware-testfile/).
3. Wait ~15-30 seconds, then check the manager:
   ```bash
   grep -a "VirusTotal: Alert" /var/ossec/logs/alerts/alerts.json | tail -5
   ```
   Expect rule **87105**, level 12, with a `positives`/`total` ratio and a
   VirusTotal permalink.
4. Clean up: delete the file and remove the Defender exclusion.
   ```powershell
   Remove-Item $t -Recurse -Force
   Remove-MpPreference -ExclusionPath $t
   ```

### In the dashboard

| Query | Shows |
|---|---|
| `rule.groups:virustotal` | every VT lookup result |
| `rule.id:87105` | actual positive hits |
| `rule.id:87103` or `87104` | lookups that ran but found nothing (proves the pipeline works even with no hit) |

## 5. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Script refuses to run, says a block already exists | A `virustotal` integration is already configured | Edit `ossec.conf` by hand instead — find it with `grep -A4 virustotal ossec.conf` |
| No alert at all after the EICAR test | Defender ate the file before FIM saw it, or FIM isn't watching that folder | Confirm the exclusion applied (`Get-MpPreference`), and confirm FIM watches that path (see the FIM kit) |
| `rule.id:87101` (error) instead of a real result | API key invalid, or rate-limited | Confirm the key works directly: `curl -s "https://www.virustotal.com/api/v3/files/<any-known-hash>" -H "x-apikey: YOUR_KEY"` |
| `ossec.log` shows `wazuh-integratord: ERROR ... Exit status was: 4` and no `87105` ever appears, even though FIM (`550`/`554`) is firing | Exit code 4 = `ERR_NO_RESPONSE_VT` in the shipped `virustotal.py` — usually the API key itself is being rejected, not a connectivity problem | Test the key directly against VirusTotal, using a hash you already have from a Wazuh FIM alert: `curl -H "x-apikey: YOUR_KEY" "https://www.virustotal.com/api/v3/files/<sha256>"` — a `{"error":{"code":"WrongCredentialsError"}}` response means the key itself is wrong/revoked, not a config bug |
| `ossec.log` shows `Enabling integration for: 'virustotal'` appearing **twice**, and `grep -c '<name>virustotal</name>' ossec.conf` returns 2 | A hand-rolled repair script used Python's `str.replace()` on `</ossec_config>` with no count limit — `ossec.conf` can legally contain more than one `<ossec_config>` root section, and an unbounded replace inserts into every one of them | Remove all VirusTotal `<integration>` blocks, then re-insert exactly one before only the **first** `</ossec_config>` (`str.replace(marker, block + marker, 1)` — explicit `count=1`). `add-virustotal-integration.sh` in this kit already does this correctly (single, bounded insert); this only bites custom/manual repair scripts. |

## 6. Active Response (optional): auto-delete instead of alert-only

Three pieces, in order:

```bash
# Server -- adds the <command>/<active-response> block
sudo bash add-virustotal-active-response.sh

# Server, optional but recommended -- adds rules 100092/100093 (clear
# success/failure alerts with the file path, instead of just the generic
# "Active response fired" rule 657). Straight from Wazuh's own official
# VirusTotal + Active Response documentation, IDs included.
sudo bash install-manager-rules.sh
```
```powershell
# Endpoint, per machine (wazuh-endpoint-toolkit\virustotal-active-response)
# -- deploys remove-threat.exe to this agent's active-response\bin\ folder
powershell -ExecutionPolicy Bypass -File .\scripts\install-active-response.ps1
```

Once all three are in place, the chain is:

```
554/550 (FIM: file added/modified)
        │
        ▼
87105 (VirusTotal: positive)
        │
        ▼
657 (Active Response: remove-threat.exe fired)
        │
        ▼
553 (file deleted)               100092 (success) or 100093 (error)
"Successfully removed threat"     — clear outcome alert with file path
in the AR log
```

Verify with:
```bash
grep 'queue/alerts/ar' /var/ossec/logs/ossec.log | tail -3        # confirms the manager's AR queue connected after restart
grep -a '"id":"657"' /var/ossec/logs/alerts/alerts.json | tail -5  # AR fired at all
grep -a '"id":"100092"\|"id":"100093"' /var/ossec/logs/alerts/alerts.json | tail -5  # AR outcome, if install-manager-rules.sh was run
```

This is irreversible and automatic — make sure alert-only behavior (§1-5
above) is confirmed working first, and that you actually want files deleted
without a human in the loop, before wiring this up across the fleet.
