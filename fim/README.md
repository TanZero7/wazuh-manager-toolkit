# FIM: manager-side check

> **Order:** do this manager side **first** → then the endpoint side, [wazuh-endpoint-toolkit → fim](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/fim) → then verify from the endpoint.
> Step-by-step with expected `[ OK ]` output: **[INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md)**.

Nothing to install. Wazuh's **built-in** FIM rules (550 modified, 553 deleted,
554 added) handle alerting out of the box. This script confirms that's actually
true on your manager (a stripped-down or heavily customized ruleset is the only
case where it wouldn't be).

```bash
sudo bash check-fim-rules.sh
```

**Next →** [wazuh-endpoint-toolkit → fim](https://github.com/TanZero7/wazuh-endpoint-toolkit/tree/main/fim)
