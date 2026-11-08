#!/bin/bash
#
# [addition -- not in the original kit] Add an Active Response
# step to the VirusTotal integration: when VirusTotal flags a file as
# malicious (rule 87105), automatically run remove-threat.exe on the
# endpoint to delete it. Without this, VirusTotal is alert-only -- a human
# has to see the dashboard alert and manually remove the file.
#
# This is SERVER-SIDE ONLY. It does not install remove-threat.exe itself --
# that's the endpoint half (see virustotal-active-response/scripts/install-active-response.ps1 in
# the wazuh-endpoint-toolkit repo), and it must exist in an agent's
# active-response/bin/remove-threat.exe before a deletion can happen.
# Recommended order: run THIS script first (manager), then the endpoint
# script on each PC, then verify from the endpoint. Until the endpoint half
# is installed, the active-response call simply fails with nothing to run.
#
# Confirmed working end-to-end on a live deployment (two endpoints): a
# malicious test file triggered FIM (554) -> VirusTotal (87105) ->
# Active Response (657, "remove-threat.exe - add") -> the file being deleted
# (553), with "Successfully removed threat" in the active-response log.
#
# Usage: sudo bash add-virustotal-active-response.sh
#
set -uo pipefail
OSSEC_DIR="/var/ossec"
OSSEC_CONF="${OSSEC_DIR}/etc/ossec.conf"
BACKUP_DIR="${OSSEC_DIR}/backup/virustotal-kit"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'
step() { echo -e "\n${CYN}==> $*${NC}"; }
ok()   { echo -e "    ${GRN}[ OK ]${NC} $*"; }
warn() { echo -e "    ${YEL}[WARN]${NC} $*"; }
die()  { echo -e "    ${RED}[FAIL]${NC} $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root"
[ -f "$OSSEC_CONF" ] || die "ossec.conf not found at $OSSEC_CONF -- is this the manager?"

step "Check the VirusTotal integration is already installed"
if ! grep -q '<name>virustotal</name>' "$OSSEC_CONF"; then
    die "No <integration><name>virustotal</name> block found -- run add-virustotal-integration.sh first. Active Response fires off rule 87105, which only exists once the VirusTotal integration itself is installed."
fi
ok "VirusTotal integration present"

step "Check for an existing remove-threat command/active-response block"
if grep -q '<name>remove-threat</name>' "$OSSEC_CONF"; then
    die "ossec.conf already has a <command><name>remove-threat</name> block -- edit it by hand to avoid duplicating. Look for it with: grep -A6 remove-threat $OSSEC_CONF"
fi
ok "No existing block -- safe to add"

step "Back up ossec.conf"
mkdir -p "$BACKUP_DIR"
BK="${BACKUP_DIR}/ossec.conf.$(date +%Y%m%d-%H%M%S).bak"
cp -p "$OSSEC_CONF" "$BK"
ok "Backed up to $BK"

step "Insert the command + active-response blocks"
# Insert before the LAST </ossec_config> (the file may legally contain more
# than one <ossec_config> root -- Wazuh's own default configs do), and only
# before that ONE tag -- not every occurrence. A naive, unbounded
# str.replace() on </ossec_config> was tried in the field and duplicated the
# block into every <ossec_config> section on a manager that had two; this
# targets exactly one insertion point instead.
python3 - "$OSSEC_CONF" <<'PYEOF'
import sys
from pathlib import Path

conf = Path(sys.argv[1])
text = conf.read_text()

command_block = """
  <command>
    <name>remove-threat</name>
    <executable>remove-threat.exe</executable>
    <timeout_allowed>no</timeout_allowed>
  </command>
"""

response_block = """
  <active-response>
    <disabled>no</disabled>
    <command>remove-threat</command>
    <location>local</location>
    <rules_id>87105</rules_id>
  </active-response>
"""

marker = "</ossec_config>"
idx = text.rfind(marker)
if idx < 0:
    print("No </ossec_config> found", file=sys.stderr)
    sys.exit(1)

text = text[:idx] + command_block + response_block + "\n" + text[idx:]
conf.write_text(text)
print("inserted")
PYEOF
[ $? -eq 0 ] || die "Insert failed -- restore from $BK"
ok "Active Response configuration added"

step "Config test"
"${OSSEC_DIR}/bin/wazuh-analysisd" -t && ok "config test passed" || die "config test FAILED -- restore from $BK and check syntax"

step "Restart"
read -r -p "    Restart wazuh-manager now? [y/N] " ANS
if [[ "$ANS" =~ ^[Yy]$ ]]; then
    systemctl restart wazuh-manager && sleep 5 && systemctl is-active --quiet wazuh-manager && ok "wazuh-manager running" || die "restart failed -- restore from $BK"
else
    warn "Not restarted -- inactive until: systemctl restart wazuh-manager"
fi

step "Done"
echo "    Confirm the queue connection after restart:"
echo "      grep 'queue/alerts/ar' /var/ossec/logs/ossec.log | tail -3"
echo "    NEXT: install the endpoint half on each PC (wazuh-endpoint-toolkit:"
echo "    virustotal-active-response), then verify from the endpoint with EICAR."
echo "    Agents pick up the new config on the manager's push cycle (5-10 min)."
echo "    After the test, on the manager:"
echo "      grep -a '\"id\":\"657\"' /var/ossec/logs/alerts/alerts.json | tail -5"
echo "    Expect the chain: 554 (added) -> 87105 (VirusTotal positive) ->"
echo "    657 (Active Response fired) -> 553 (file deleted)."
