# Wazuh Manager Toolkit

**Manager-side** (Linux) companion to
[wazuh-endpoint-toolkit](https://github.com/TanZero7/wazuh-endpoint-toolkit):
custom detection rules, integrations and verification scripts for a Wazuh
SIEM, one folder per capability. Everything that runs on Windows endpoints lives
in the endpoint repo; everything here runs on the Wazuh manager.

## Capabilities

| Folder | Type | What it does |
|---|---|---|
| [suricata](suricata) | **install (required)** | Custom rules 100200–100232 that turn Suricata's DNS/TLS/HTTP events into searchable visibility alerts (Wazuh's stock rules discard them at level 0) |
| [yara](yara) | **install** | Rules 100700/100701 for YARA scan results + the `ossec.conf` active-response block that triggers the scan on every FIM change |
| [virustotal](virustotal) | **install** | Official VirusTotal hash-reputation integration, optional Active Response (auto-delete on a positive), and rules 100092/100093 for clear AR outcome alerts |
| [fim](fim) | verify only | Confirms Wazuh's built-in FIM rules (550/553/554) are present |
| [sysmon](sysmon) | verify only | Confirms Wazuh's built-in Sysmon ruleset (~150 rules) is present |
| [vulnerability-detection](vulnerability-detection) | verify / diagnose | Checks the built-in CVE module is enabled and producing data, with a step-by-step diagnosis path for agents that "look empty" |

## Usage

```bash
git clone https://github.com/TanZero7/wazuh-manager-toolkit.git
cd wazuh-manager-toolkit/<capability>
sudo bash <script>.sh
```

Each folder's README says exactly which script to run and what output to expect.
Step-by-step guides covering both sides together are in the endpoint repo's
[`guides/`](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/guides).

## How the scripts behave

- **Back up first.** Anything that touches `/var/ossec/etc` saves a timestamped
  copy under `/var/ossec/backup/` before changing it.
- **Validate before restart.** Rule installers validate with `wazuh-logtest`
  against sample events, or `wazuh-analysisd -t`, *before* restarting the manager,
  because a malformed rules file stops `wazuh-manager` from starting at all.
- **`ossec.conf` edits are deliberately conservative.** The YARA active-response
  block is pasted by hand (`active-response-block.xml` explains why). The
  VirusTotal scripts edit `ossec.conf` automatically but config-test with
  `wazuh-analysisd -t` and refuse to restart on a failure.
- **Safe to re-run.** Installers are idempotent.

## Requirements

- Wazuh manager 4.x (tested with 4.14), `sudo` access
- Internet access from the manager for VirusTotal lookups and CVE feed updates
- A VirusTotal API key (for `virustotal/` only)

## License

See [LICENSE](LICENSE).
