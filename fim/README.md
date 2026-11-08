# FIM: manager-side check

Nothing to install. Wazuh's **built-in** FIM rules (550 modified, 553 deleted,
554 added) handle alerting out of the box. This script confirms that's actually
true on your manager (a stripped-down or heavily customized ruleset is the only
case where it wouldn't be).

```bash
sudo bash check-fim-rules.sh
```

The endpoint side (Desktop + Downloads realtime scope, no-event-loss tuning) is
`fim/` in [wazuh-endpoint-toolkit](https://github.com/TanZero7/wazuh-endpoint-toolkit).
