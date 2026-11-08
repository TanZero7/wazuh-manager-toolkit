# Sysmon: manager-side check

Nothing to install. Wazuh's **built-in** Sysmon ruleset (~150 rules across event
IDs 1, 3, 7, 8, 10, 11, 13, 20) does the detection. This script confirms the
expected rule files are present and `wazuh-analysisd` is running.

```bash
sudo bash check-sysmon-rules.sh
```

Endpoint side: `sysmon/` in [wazuh-endpoint-toolkit](https://github.com/TanZero7/wazuh-endpoint-toolkit).
Step by step: [SYSMON-YARA-SETUP-GUIDE.md § 1.2](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/guides/SYSMON-YARA-SETUP-GUIDE.md#12-server-verification-only-nothing-to-install).
