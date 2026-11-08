#!/bin/bash
#
# [addition -- not in the original kit]
# Install the VirusTotal Active Response outcome rules (100092/100093) on
# the Wazuh MANAGER. These come straight from Wazuh's own official
# VirusTotal + Active Response documentation.
#
# Run this AFTER both add-virustotal-integration.sh and
# add-virustotal-active-response.sh -- these rules chain off rule 657
# (Active Response fired), so they need that already configured, though
# nothing here will fail if you run it out of order; the rules just won't
# have anything to match yet.
#
# Usage: sudo bash install-manager-rules.sh
#
set -uo pipefail
OSSEC_DIR="/var/ossec"
RULES_DEST="${OSSEC_DIR}/etc/rules/local_rules_virustotal.xml"
SRC_FILE="$(dirname "$0")/local_rules_virustotal.xml"
BACKUP_DIR="${OSSEC_DIR}/backup/virustotal-kit"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'
step() { echo -e "\n${CYN}==> $*${NC}"; }
ok()   { echo -e "    ${GRN}[ OK ]${NC} $*"; }
warn() { echo -e "    ${YEL}[WARN]${NC} $*"; }
fail() { echo -e "    ${RED}[FAIL]${NC} $*"; }
die()  { fail "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo bash $0)"
[ -d "$OSSEC_DIR" ]  || die "No Wazuh installation at $OSSEC_DIR -- is this the manager?"
[ -f "$SRC_FILE" ]   || die "local_rules_virustotal.xml not found next to this script"

step "Back up any existing copy"
mkdir -p "$BACKUP_DIR"
[ -f "$RULES_DEST" ] && cp -p "$RULES_DEST" "${BACKUP_DIR}/local_rules_virustotal.xml.$(date +%Y%m%d-%H%M%S)" && ok "Backed up" || ok "No existing file"

step "Install"
cp "$SRC_FILE" "$RULES_DEST"
chown wazuh:wazuh "$RULES_DEST" 2>/dev/null || chown ossec:ossec "$RULES_DEST" 2>/dev/null || warn "Could not set ownership"
chmod 660 "$RULES_DEST"
ok "Installed $RULES_DEST"

step "Config test"
"${OSSEC_DIR}/bin/wazuh-analysisd" -t && ok "config test passed" || die "config test failed -- check the rules file"

step "Restart"
read -r -p "    Restart wazuh-manager now? [y/N] " ANS
if [[ "$ANS" =~ ^[Yy]$ ]]; then
    systemctl restart wazuh-manager && sleep 5 && systemctl is-active --quiet wazuh-manager && ok "wazuh-manager running" || die "restart failed"
else
    warn "Not restarted -- rules are on disk but inactive until: systemctl restart wazuh-manager"
fi

step "Done"
cat <<EOF
    Fire-test (needs the full chain already installed -- integration,
    active response, and remove-threat.exe on the agent): drop an EICAR
    test file in a FIM-watched directory, then:

      rule.id:(100092 OR 100093)     in the dashboard, or
      grep -a '"id":"100092"\|"id":"100093"' /var/ossec/logs/alerts/alerts.json

EOF
