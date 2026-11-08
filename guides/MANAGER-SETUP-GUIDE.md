# Manager Setup Guide

**Every manager-side step, in order: do this BEFORE the endpoint guides.**

> **Install order: manager first (this guide), then endpoint, then verify**
>
> 1. **Manager**: this guide.
> 2. **Endpoints**: [ENDPOINT-SETUP-GUIDE.md](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/guides/ENDPOINT-SETUP-GUIDE.md)
>    (FIM, Suricata, VirusTotal) and
>    [SYSMON-YARA-SETUP-GUIDE.md](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/guides/SYSMON-YARA-SETUP-GUIDE.md).
> 3. **Verify**: at the end of each endpoint guide. Verification is always done
>    from the endpoint, once both sides are installed.

Every command is written out exactly as it should be typed. Manager scripts
print `[ OK ]` for each successful step and `[FAIL]` (then stop) if something is
wrong. A failing script never restarts the manager with a bad config.

> **If a command shows `[FAIL]` or an error, stop and fix it before moving on.**
> When a script asks `Restart wazuh-manager now? [y/N]`, type **`y`**.

---

## Before you start

- [ ] SSH access to the Wazuh manager with `sudo` rights:
      ```bash
      ssh <your-admin-login>@<WAZUH_MANAGER_IP>
      ```
- [ ] This repo cloned into your home folder on the manager:
      ```bash
      cd ~
      git clone https://github.com/TanZero7/wazuh-manager-toolkit.git
      ```
- [ ] A VirusTotal API key (only for section 4).
- [ ] The manager has a **static IP** (agents connect by IP; a changed address
      silently disconnects every agent).

---

## 1. FIM: check the built-in rules

```bash
cd ~/wazuh-manager-toolkit/fim
sudo bash check-fim-rules.sh
```

**OK** = `rule 550 present`, `rule 553 present`, `rule 554 present`,
`ruleset/rules is loaded`, `wazuh-analysisd is running`. Nothing to install.

## 2. Sysmon: check the built-in ruleset

```bash
cd ~/wazuh-manager-toolkit/sysmon
sudo bash check-sysmon-rules.sh
```

**OK** = `all 10 expected Sysmon rule files present` (or found by content) and
`wazuh-analysisd is running`. Nothing to install.

## 3. Suricata: install the visibility rules (required)

```bash
cd ~/wazuh-manager-toolkit/suricata
sudo bash install-manager-rules.sh
```

**OK** = `Manager version: …` (**write this down**: the Windows agents must be
no newer), `Found 0475-suricata_rules.xml`, `Installed …local_rules_suricata.xml`,
then after you answer `y`, `wazuh-manager is running`.

"Sample … missing, skipping" warnings during validation are expected in this
release (see [suricata/INTEGRATION-GUIDE.md](../suricata/INTEGRATION-GUIDE.md#2-install-the-rules)).

## 4. VirusTotal: integration (+ optional Active Response)

```bash
cd ~/wazuh-manager-toolkit/virustotal
sudo bash add-virustotal-integration.sh <YOUR_VIRUSTOTAL_API_KEY>
```

**OK** = `Integration block inserted`, `config test passed`, `wazuh-manager running`.

Only if you want files flagged by VirusTotal **deleted automatically**:

```bash
sudo bash add-virustotal-active-response.sh
sudo bash install-manager-rules.sh
```

**OK** = `Active Response configuration added`, `config test passed`,
`wazuh-manager running` (both scripts).

## 5. YARA: rules + active-response block

### 5.1 Install the rules

```bash
cd ~/wazuh-manager-toolkit/yara
sudo bash install-manager-rules.sh
```

**OK** = `yara-match.json -> rule 100700 (as expected)`,
`yara-clean.json -> rule 100701 (as expected)`, `All 2/2 rule validations passed`.
**Do not continue if the 100700 line fails.**

### 5.2 Paste the active-response block (manual)

```bash
sudo nano /var/ossec/etc/ossec.conf
```

Inside `<ossec_config>`, near the other `<command>` definitions, paste:

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

Save (`Ctrl+O`, `Enter`, `Ctrl+X`), then **test before restarting**:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo systemctl restart wazuh-manager
```

**OK** = the config test reports no errors, and `sudo systemctl is-active wazuh-manager`
prints `active`. If the test reports an error, fix the pasted block. Don't restart
until it's clean.

## 6. Vulnerability Detection: check (optional)

```bash
cd ~/wazuh-manager-toolkit/vulnerability-detection
sudo bash check-vulnerability-detection.sh
```

**OK** = `enabled`, `wazuh-modulesd is running`. New agents take up to about an
hour to show CVEs.

---

## 7. Finished: checklist

- [ ] FIM and Sysmon checks: all `[ OK ]`
- [ ] Suricata rules installed, manager restarted, **manager version noted**
- [ ] VirusTotal integration added (and Active Response, if wanted)
- [ ] YARA rules: `All 2/2 rule validations passed`
- [ ] YARA active-response block pasted, config-tested, manager restarted

> ⏳ Agents receive new active-response config (`ar.conf`) on the manager's push
> cycle. Allow **5–10 minutes** before endpoint checks that depend on it will pass.

**Next →** [ENDPOINT-SETUP-GUIDE.md](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/guides/ENDPOINT-SETUP-GUIDE.md),
then [SYSMON-YARA-SETUP-GUIDE.md](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/guides/SYSMON-YARA-SETUP-GUIDE.md).
