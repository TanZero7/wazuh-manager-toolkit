# YARA: manager-side rules + active-response wiring

Turns the YARA scan results the endpoint writes into Wazuh alerts, and tells the
manager to trigger the scan on every FIM add/change.

| File | Purpose |
|---|---|
| `local_rules_yara.xml` | rule **100700** (match) / **100701** (clean scan) |
| `install-manager-rules.sh` | backs up, installs and validates the rules with `wazuh-logtest` against `logtest-samples/`, then restarts |
| `active-response-block.xml` | the `<command>` + `<active-response>` block to paste into `ossec.conf` **by hand** (see its header for why this stays manual) |
| `logtest-samples/` | sample match / clean events the installer uses to prove the rules fire |

## Install

```bash
sudo bash install-manager-rules.sh
```

Expect `[ OK ] yara-match.json -> rule 100700`. Then paste
`active-response-block.xml` into `/var/ossec/etc/ossec.conf`, run
`sudo /var/ossec/bin/wazuh-analysisd -t`, and only if that's clean,
`sudo systemctl restart wazuh-manager`.

> **Bug fixed in this version:** rule 100700 used to match `yara_rule` against
> `\.+` (literal dots), so real matches never alerted. If an older copy is
> installed, re-run `install-manager-rules.sh` and confirm the 100700 check passes.

Endpoint side: `yara/` in [wazuh-endpoint-toolkit](https://github.com/TanZero7/wazuh-endpoint-toolkit).
Step by step: [SYSMON-YARA-SETUP-GUIDE.md § 2](https://github.com/TanZero7/wazuh-endpoint-toolkit/blob/main/guides/SYSMON-YARA-SETUP-GUIDE.md#2-yara).
