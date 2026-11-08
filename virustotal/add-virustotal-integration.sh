#!/bin/bash
#
# Add the standard Wazuh VirusTotal integration block to ossec.conf.
# This follows Wazuh's own official documentation directly -- there is no
# custom file needed for this integration, just the standard <integration>
# block with your API key. This script inserts it safely (backs up first,
# config-tests before restarting) rather than requiring a manual paste, since
# unlike an active-response block, this element is low-risk and well-defined.
#
# Usage: sudo bash add-virustotal-integration.sh <API_KEY>
#
set -uo pipefail
OSSEC_DIR="/var/ossec"
OSSEC_CONF="${OSSEC_DIR}/etc/ossec.conf"
API_KEY="${1:-}"
RULE_IDS="550,554"   # FIM: file modified, file added

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'
step() { echo -e "\n${CYN}==> $*${NC}"; }
ok()   { echo -e "    ${GRN}[ OK ]${NC} $*"; }
warn() { echo -e "    ${YEL}[WARN]${NC} $*"; }
die()  { echo -e "    ${RED}[FAIL]${NC} $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root"
[ -f "$OSSEC_CONF" ] || die "ossec.conf not found at $OSSEC_CONF -- is this the manager?"
[ -n "$API_KEY" ] || die "Usage: sudo bash $0 <VIRUSTOTAL_API_KEY>"

step "Check for an existing VirusTotal block"
if grep -q '<name>virustotal</name>' "$OSSEC_CONF"; then
    die "ossec.conf already has a <integration><name>virustotal</name> block -- edit it by hand to avoid duplicating. Look for it with: grep -A4 virustotal $OSSEC_CONF"
fi
ok "No existing block -- safe to add"

step "Back up ossec.conf"
BK="${OSSEC_DIR}/backup/ossec.conf.$(date +%Y%m%d-%H%M%S).bak"
mkdir -p "$(dirname "$BK")"
cp -p "$OSSEC_CONF" "$BK"
ok "Backed up to $BK"

step "Insert the integration block"
# Insert before the LAST </ossec_config> (the file may legally contain more
# than one <ossec_config> root -- Wazuh's own default configs do).
python3 - "$OSSEC_CONF" "$API_KEY" "$RULE_IDS" <<'PYEOF'
import sys
path, api_key, rule_ids = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, 'r', encoding='utf-8') as f:
    conf = f.read()
block = f"""
  <integration>
    <name>virustotal</name>
    <api_key>{api_key}</api_key>
    <rule_id>{rule_ids}</rule_id>
    <alert_format>json</alert_format>
  </integration>
"""
idx = conf.rfind('</ossec_config>')
if idx < 0:
    print("No </ossec_config> found", file=sys.stderr)
    sys.exit(1)
conf = conf[:idx] + block + '\n' + conf[idx:]
with open(path, 'w', encoding='utf-8') as f:
    f.write(conf)
print("inserted")
PYEOF
[ $? -eq 0 ] || die "Insert failed -- restore from $BK"
ok "Integration block inserted"

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
echo "    Fire-test: drop an EICAR test file in a FIM-watched directory on an"
echo "    agent, then check for rule.groups:virustotal in the dashboard."
echo "    (get EICAR from https://www.eicar.org/download-anti-malware-testfile/"
echo "     -- your endpoint AV will likely quarantine it instantly, which is"
echo "     correct behavior; a brief Defender exclusion on a throwaway test"
echo "     folder is the usual way to get it to sit still long enough to test)"
