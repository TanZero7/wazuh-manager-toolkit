#!/bin/bash
#
# Confirm the manager side of FIM alerting is present. Wazuh ships this
# OUT OF THE BOX -- rules 550 (modified), 553 (deleted), 554 (added), plus
# the surrounding syscheck rule group, live in the DEFAULT ruleset. There is
# nothing to install here; this script exists purely to verify it
# ("confirm the built-in feature is live", not "install something custom").
#
# Usage: sudo bash check-fim-rules.sh
#
set -uo pipefail
OSSEC_DIR="/var/ossec"

GRN='\033[0;32m'; RED='\033[0;31m'; CYN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "    ${GRN}[ OK ]${NC} $*"; }
fail() { echo -e "    ${RED}[FAIL]${NC} $*"; }
step() { echo -e "\n${CYN}==> $*${NC}"; }

step "Built-in FIM rule file"
RULEFILE=$(grep -l 'id="554"' "${OSSEC_DIR}/ruleset/rules"/*.xml 2>/dev/null | head -1)
if [ -n "$RULEFILE" ]; then
    ok "found in $(basename "$RULEFILE")"
else
    fail "no rule file containing id=\"554\" found under ${OSSEC_DIR}/ruleset/rules -- unusual ruleset install, check manually"
fi

step "The three core FIM rules"
for rid in 550 553 554; do
    if grep -q "id=\"${rid}\"" "${OSSEC_DIR}/ruleset/rules"/*.xml 2>/dev/null; then
        ok "rule ${rid} present"
    else
        fail "rule ${rid} NOT found"
    fi
done

step "ossec.conf loads the default ruleset"
if grep -q '<rule_dir>ruleset/rules</rule_dir>' "${OSSEC_DIR}/etc/ossec.conf"; then
    ok "ruleset/rules is loaded"
else
    fail "ruleset/rules not referenced in ossec.conf -- unusual, check the <ruleset> block"
fi

step "wazuh-analysisd running"
# Deliberately not "wazuh-control status | grep -q ...": under set -o pipefail
# that reports the PIPELINE's exit status, and wazuh-control returns nonzero
# whenever ANY daemon is stopped (clusterd/maild/agentlessd are off by
# default) -- so a healthy manager was reporting as "analysisd not running"
# here until this was caught and fixed. Capture first, match with case.
STATUS_OUT=$("${OSSEC_DIR}/bin/wazuh-control" status 2>/dev/null || true)
case "$STATUS_OUT" in
    *"wazuh-analysisd is running"*) ok "wazuh-analysisd is running" ;;
    *) fail "wazuh-analysisd is not running" ;;
esac

echo
echo "If everything above is OK, no server-side install is needed for FIM"
echo "alerting -- just make sure at least one agent has the fim/ folder"
echo "of wazuh-endpoint-toolkit (or any <syscheck> scope) installed and watching a"
echo "directory. Fire-test: create/edit/delete a file in a watched folder"
echo "and confirm alerts for rule.id:550, 553, 554."
