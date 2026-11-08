#!/bin/bash
#
# Install the YARA integration rules on the Wazuh MANAGER.
# Copy this script and local_rules_yara.xml to the manager, then:
#     sudo bash install-manager-rules.sh
#
# This installs and validates the RULES FILE ONLY. The <command>/
# <active-response> block in active-response-block.xml still needs to be
# pasted into ossec.conf BY HAND (see that file's own header comment for
# why) before anything actually triggers a YARA scan.
#
# Safe to re-run.

set -uo pipefail

OSSEC_DIR="/var/ossec"
RULES_DEST="${OSSEC_DIR}/etc/rules/local_rules_yara.xml"
SRC_FILE="$(dirname "$0")/local_rules_yara.xml"
SAMPLES_DIR="$(dirname "$0")/logtest-samples"
BACKUP_DIR="${OSSEC_DIR}/backup/yara-kit"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'
step() { echo -e "\n${CYN}==> $*${NC}"; }
ok()   { echo -e "    ${GRN}[ OK ]${NC} $*"; }
warn() { echo -e "    ${YEL}[WARN]${NC} $*"; }
fail() { echo -e "    ${RED}[FAIL]${NC} $*"; }
die()  { fail "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo bash $0)"
[ -d "$OSSEC_DIR" ]  || die "No Wazuh installation at $OSSEC_DIR -- is this the manager?"
[ -f "$SRC_FILE" ]   || die "local_rules_yara.xml not found next to this script"

step "Manager identity"
"${OSSEC_DIR}/bin/wazuh-control" info 2>/dev/null || warn "wazuh-control info failed"
STATUS_OUT=$("${OSSEC_DIR}/bin/wazuh-control" status 2>/dev/null || true)
case "$STATUS_OUT" in
    *"wazuh-analysisd is running"*) ok "wazuh-analysisd is running" ;;
    *) warn "wazuh-analysisd does not appear to be running." ;;
esac

step "Back up any existing copy"
mkdir -p "$BACKUP_DIR"
if [ -f "$RULES_DEST" ]; then
    BK="${BACKUP_DIR}/local_rules_yara.xml.$(date +%Y%m%d-%H%M%S)"
    cp -p "$RULES_DEST" "$BK"
    ok "Backed up existing rules to $BK"
else
    ok "No existing file to back up"
fi

step "Install rules"
cp "$SRC_FILE" "$RULES_DEST"
chown wazuh:wazuh "$RULES_DEST" 2>/dev/null || warn "Could not set ownership"
chmod 660 "$RULES_DEST"
ok "Installed $RULES_DEST"

step "Validate rules with wazuh-logtest (before restarting)"
LOGTEST="${OSSEC_DIR}/bin/wazuh-logtest"
if [ ! -x "$LOGTEST" ]; then
    warn "wazuh-logtest not available; skipping validation"
else
    PASS=0; TOTAL=0
    declare -A EXPECT=( ["yara-match.json"]="100700" ["yara-clean.json"]="100701" )
    for sample in "${!EXPECT[@]}"; do
        SF="${SAMPLES_DIR}/${sample}"
        [ -f "$SF" ] || { warn "Sample $sample missing, skipping"; continue; }
        TOTAL=$((TOTAL+1)); WANT="${EXPECT[$sample]}"
        OUT=$(tr -d '\n' < "$SF" | "$LOGTEST" -v 2>&1)
        GOT=$(echo "$OUT" | sed -n "s/^[[:space:]]*id: '\([0-9]*\)'.*/\1/p" | tail -1)
        if [ "$GOT" = "$WANT" ]; then
            ok "${sample} -> rule ${WANT} (as expected)"; PASS=$((PASS+1))
        else
            fail "${sample} -> expected ${WANT}, got ${GOT:-no match}"
        fi
    done
    echo
    if [ "$TOTAL" -gt 0 ] && [ "$PASS" -eq "$TOTAL" ]; then
        ok "All ${PASS}/${TOTAL} rule validations passed"
    else
        warn "${PASS}/${TOTAL} validations passed -- review before relying on the dashboard"
    fi
fi

step "Active-response block (manual step -- not applied by this script)"
cat <<EOF

    The rules file is installed, but nothing triggers a YARA scan yet.
    Paste the contents of active-response-block.xml into
    ${OSSEC_DIR}/etc/ossec.conf (inside <ossec_config>, near the other
    <command> definitions), then:

        ${OSSEC_DIR}/bin/wazuh-analysisd -t     # config test
        systemctl restart wazuh-manager

    See active-response-block.xml's header comment for why this one step
    stays manual.

EOF

step "Done"
cat <<EOF
    Dashboard queries to try (after the active-response block is in and an
    endpoint with the YARA kit installed has triggered a FIM change):

      rule.groups:yara_alert          confirmed YARA matches
      rule.id:100700                  matches only
      rule.id:100701                  clean scans (proves the pipeline runs)

EOF
