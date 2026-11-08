# Changelog

## v1.0.0 (2026-11): production rollout release

### Added
- **Suricata rules** (`suricata/`): custom rules 100200–100232 that turn
  Suricata's DNS, TLS and HTTP events into searchable visibility alerts, plus
  severity-based signature alerts, a burst/scan correlation rule and detections
  for DNS tunnelling, abused TLDs, no-SNI TLS, cleartext executable downloads and
  scripted HTTP clients (mapped to MITRE ATT&CK).
- **YARA rules + active-response block** (`yara/`): rules 100700/100701 and the
  `ossec.conf` block that triggers a YARA scan on every FIM change, with
  `wazuh-logtest` sample events.
- **VirusTotal** (`virustotal/`): scripts for the official integration, optional
  auto-delete Active Response, and rules 100092/100093 for clear outcome alerts.
- **Verify scripts** for the built-in FIM, Sysmon and Vulnerability Detection
  rulesets.
- **Step-by-step manager guide** (`guides/MANAGER-SETUP-GUIDE.md`).

### Fixed
- **YARA rule 100700 could never fire.** Its `yara_rule` pattern had been
  changed during rollout from `\.+` to `.+`. In Wazuh's OS_Regex a bare `.` is a
  literal dot, so real matches never alerted. Restored to `\.+`; the rule now
  ships with logtest samples (`yara/logtest-samples/`) and the installer runs
  both through `wazuh-logtest` before restarting. Full write-up in the
  endpoint repo's [CHANGELOG](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/CHANGELOG.md).
