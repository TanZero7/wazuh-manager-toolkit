# Sysmon: manager-side check

> **Order:** do this manager side **first** → then the endpoint side, [wazuh-endpoint-toolkit → sysmon](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/sysmon) → then verify from the endpoint.
> Step-by-step with expected `[ OK ]` output: **[INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md)**.

Nothing to install. Wazuh's **built-in** Sysmon ruleset (~150 rules across event
IDs 1, 3, 7, 8, 10, 11, 13, 20) does the detection. This script confirms the
expected rule files are present and `wazuh-analysisd` is running.

```bash
sudo bash check-sysmon-rules.sh
```

**Next →** [wazuh-endpoint-toolkit → sysmon](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/sysmon)
