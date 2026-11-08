#!/bin/bash
#
# Confirm the manager side of Sysmon detection is present. Wazuh ships this
# OUT OF THE BOX -- the Sysmon ruleset (event IDs 1,3,7,8,10,11,13,20; ~150
# rules total) lives in the DEFAULT ruleset. There is nothing to install
# here; this script exists purely to verify it
# ("confirm the built-in feature is live", not "install something custom").
#
# Usage: sudo bash check-sysmon-rules.sh
#
set -uo pipefail
OSSEC_DIR="/var/ossec"
RULES_DIR="${OSSEC_DIR}/ruleset/rules"

GRN='\033[0;32m'; RED='\033[0;31m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "    ${GRN}[ OK ]${NC} $*"; }
fail() { echo -e "    ${RED}[FAIL]${NC} $*"; }
warn() { echo -e "    ${YEL}[WARN]${NC} $*"; }
step() { echo -e "\n${CYN}==> $*${NC}"; }

step "Sysmon rule files (built-in)"
# Filenames as shipped in Wazuh 4.14.x; a future Wazuh version could rename
# these, so this also falls back to a content-based search if the exact
# names aren't found.
EXPECTED=(0330-sysmon_rules.xml 0595-win-sysmon_rules.xml 0800-sysmon_id_1.xml
          0810-sysmon_id_3.xml 0820-sysmon_id_7.xml 0830-sysmon_id_11.xml
          0860-sysmon_id_13.xml 0870-sysmon_id_8.xml 0945-sysmon_id_10.xml
          0950-sysmon_id_20.xml)
FOUND=0
for f in "${EXPECTED[@]}"; do
    if [ -f "${RULES_DIR}/${f}" ]; then FOUND=$((FOUND+1)); fi
done
if [ "$FOUND" -eq "${#EXPECTED[@]}" ]; then
    ok "all ${#EXPECTED[@]} expected Sysmon rule files present"
elif [ "$FOUND" -gt 0 ]; then
    warn "${FOUND}/${#EXPECTED[@]} expected files found -- ruleset may have been customized or this is a different Wazuh version"
else
    warn "none of the expected filenames found -- falling back to content search"
    ALT=$(grep -rl 'sysmon_event1\|Microsoft-Windows-Sysmon' "${RULES_DIR}"/*.xml 2>/dev/null | wc -l)
    if [ "$ALT" -gt 0 ]; then ok "found $ALT rule file(s) referencing Sysmon by content instead"
    else fail "no Sysmon rule coverage found at all in ${RULES_DIR} -- check your Wazuh ruleset installation"; fi
fi

step "Rule count sanity check"
COUNT=$(grep -ho '<rule id="6[0-9]\{4\}"\|<rule id="9[0-9]\{4\}"' "${RULES_DIR}"/0800-sysmon_id_1.xml "${RULES_DIR}"/0595-win-sysmon_rules.xml 2>/dev/null | wc -l)
if [ "$COUNT" -gt 0 ]; then ok "$COUNT rule definitions counted in the core Sysmon files"
else warn "could not count rules -- not fatal, just informational"; fi

step "wazuh-analysisd running"
STATUS_OUT=$("${OSSEC_DIR}/bin/wazuh-control" status 2>/dev/null || true)
case "$STATUS_OUT" in
    *"wazuh-analysisd is running"*) ok "wazuh-analysisd is running" ;;
    *) fail "wazuh-analysisd is not running" ;;
esac

echo
echo "If everything above is OK, no server-side install is needed for Sysmon"
echo "detections -- just make sure the sysmon/ folder of wazuh-endpoint-toolkit is"
echo "installed on at least one agent. Fire-test: run any command in a"
echo "fresh cmd.exe/powershell.exe on that endpoint and confirm alerts under"
echo "rule.groups:sysmon_event1 within a few seconds."
