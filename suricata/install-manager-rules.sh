#!/bin/bash
#
# Install the custom Suricata visibility rules on the Wazuh MANAGER.
#
# Copy this script and local_rules_suricata.xml to the manager, then:
#     sudo bash install-manager-rules.sh
#
# What it does:
#   1. Reports the manager version  <-- the number that decides whether the Windows
#      agent needs downgrading. This is the authoritative source; do not rely on
#      anyone's recollection.
#   2. Backs up any existing copy of the rules file.
#   3. Installs local_rules_suricata.xml with the ownership and permissions Wazuh needs.
#   4. Validates every rule against sample Suricata events using wazuh-logtest,
#      BEFORE restarting. A malformed rules file makes wazuh-manager refuse to start,
#      so this ordering matters.
#   5. Restarts the manager and confirms it came back up.
#
# Safe to re-run.

set -uo pipefail

OSSEC_DIR="/var/ossec"
RULES_DEST="${OSSEC_DIR}/etc/rules/local_rules_suricata.xml"
SRC_FILE="$(dirname "$0")/local_rules_suricata.xml"
SAMPLES_DIR="$(dirname "$0")/logtest-samples"
BACKUP_DIR="${OSSEC_DIR}/backup/suricata-kit"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'
step() { echo -e "\n${CYN}==> $*${NC}"; }
ok()   { echo -e "    ${GRN}[ OK ]${NC} $*"; }
warn() { echo -e "    ${YEL}[WARN]${NC} $*"; }
fail() { echo -e "    ${RED}[FAIL]${NC} $*"; }
die()  { fail "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo bash $0)"
[ -d "$OSSEC_DIR" ]  || die "No Wazuh installation at $OSSEC_DIR -- is this the manager?"
[ -f "$SRC_FILE" ]   || die "local_rules_suricata.xml not found next to this script"

# ---------------------------------------------------------------------------
step "Manager identity and version"

if [ -x "${OSSEC_DIR}/bin/wazuh-control" ]; then
    "${OSSEC_DIR}/bin/wazuh-control" info
    MGR_VERSION=$("${OSSEC_DIR}/bin/wazuh-control" info | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d 'v')
    ok "Manager version: ${MGR_VERSION}"
    echo
    echo "    >>> Use this exact version for the Windows agent:"
    echo "    >>>     .\\01-fix-agent-version.ps1 -ManagerVersion ${MGR_VERSION}"
    echo
else
    warn "wazuh-control not found; cannot determine version"
    MGR_VERSION="unknown"
fi

# Deliberately NOT "wazuh-control status | grep -q ...".
# This script runs under "set -o pipefail", and grep -q exits the moment it matches,
# which SIGPIPEs wazuh-control upstream. The pipeline then reports the upstream's 141
# rather than grep's 0, so a healthy manager was being reported as "analysisd not
# running". Capturing first and pattern-matching with case avoids the pipe altogether.
STATUS_OUT=$("${OSSEC_DIR}/bin/wazuh-control" status 2>/dev/null || true)
case "$STATUS_OUT" in
    *"wazuh-analysisd is running"*) ok "wazuh-analysisd is running" ;;
    *) warn "wazuh-analysisd does not appear to be running. This may not be a manager, or it is stopped." ;;
esac

# ---------------------------------------------------------------------------
step "Confirm the built-in Suricata ruleset is present"

BUILTIN=$(find "${OSSEC_DIR}/ruleset/rules" -name '*suricata*' 2>/dev/null | head -1)
if [ -n "$BUILTIN" ]; then
    ok "Found $(basename "$BUILTIN")"
    echo "    Parent rules this kit chains off:"
    grep -oE 'rule id="866[0-9]{2}" level="[0-9]+"' "$BUILTIN" | sed 's/^/      /'
else
    warn "No built-in Suricata ruleset found. Custom rules reference 86601-86604 via if_sid"
    warn "and will not load without them. Check your ruleset version."
fi

# ---------------------------------------------------------------------------
step "Back up any existing custom rules"

mkdir -p "$BACKUP_DIR"
if [ -f "$RULES_DEST" ]; then
    BK="${BACKUP_DIR}/local_rules_suricata.xml.$(date +%Y%m%d-%H%M%S)"
    cp -p "$RULES_DEST" "$BK"
    ok "Backed up existing rules to $BK"
else
    ok "No existing file to back up"
fi

# ---------------------------------------------------------------------------
step "Install rules"

cp "$SRC_FILE" "$RULES_DEST"
chown wazuh:wazuh "$RULES_DEST" 2>/dev/null || chown ossec:ossec "$RULES_DEST" 2>/dev/null || warn "Could not set ownership"
chmod 660 "$RULES_DEST"
ok "Installed $RULES_DEST"
ls -l "$RULES_DEST" | sed 's/^/      /'

# ---------------------------------------------------------------------------
step "Validate rules with wazuh-logtest (before restarting)"

# A broken rules file prevents wazuh-manager from starting at all, so everything is
# checked here first. logtest loads the full ruleset including this new file.

LOGTEST="${OSSEC_DIR}/bin/wazuh-logtest"
if [ ! -x "$LOGTEST" ]; then
    warn "wazuh-logtest not available; skipping validation (Wazuh 4.2+ required)"
else
    PASS=0; TOTAL=0
    declare -A EXPECT=(
        ["dns-query.json"]="100210"
        ["dns-tunnel.json"]="100211"
        ["tls-sni.json"]="100220"
        ["http-request.json"]="100230"
        ["http-exe-download.json"]="100231"
        ["alert-high.json"]="100200"
    )

    for sample in "${!EXPECT[@]}"; do
        SF="${SAMPLES_DIR}/${sample}"
        [ -f "$SF" ] || { warn "Sample $sample missing, skipping"; continue; }
        TOTAL=$((TOTAL+1))
        WANT="${EXPECT[$sample]}"

        # -v only, never "-q -v": -q suppresses ALL output including the Phase 3 result,
        # so every check silently reports "no match" and the validation looks 0/N even
        # when the rules are fine. Learned the hard way.
        OUT=$(tr -d '\n' < "$SF" | "$LOGTEST" -v 2>&1)

        # Take the LAST id, which is the final matching rule after child traversal.
        GOT=$(echo "$OUT" | sed -n "s/^[[:space:]]*id: '\([0-9]*\)'.*/\1/p" | tail -1)

        if [ "$GOT" = "$WANT" ]; then
            ok "${sample} -> rule ${WANT} (as expected)"
            PASS=$((PASS+1))
        else
            fail "${sample} -> expected ${WANT}, got ${GOT:-no match}"
            echo "$OUT" | sed -n "s/^[[:space:]]*\(id\|level\|description\): \(.*\)/        \1: \2/p" | tail -3
            echo "$OUT" | grep -oE "Trying rule: [0-9]+" | tail -6 | sed 's/^/        /'
        fi
    done

    echo
    if [ "$TOTAL" -gt 0 ] && [ "$PASS" -eq "$TOTAL" ]; then
        ok "All ${PASS}/${TOTAL} rule validations passed"
    else
        warn "${PASS}/${TOTAL} validations passed -- review the failures above before relying on the dashboard"
        warn "Rules are installed regardless; a failure here means a rule will not fire, not that the manager will break."
    fi
fi

# ---------------------------------------------------------------------------
step "Restart wazuh-manager"

read -r -p "    Restart wazuh-manager now? [y/N] " ANS
if [[ "$ANS" =~ ^[Yy]$ ]]; then
    if systemctl restart wazuh-manager; then
        sleep 8
        if systemctl is-active --quiet wazuh-manager; then
            ok "wazuh-manager is running"
            "${OSSEC_DIR}/bin/wazuh-control" status | sed 's/^/      /'
        else
            fail "wazuh-manager failed to start"
            echo "    Recent errors:"
            tail -30 "${OSSEC_DIR}/logs/ossec.log" | grep -iE 'error|critical' | sed 's/^/      /'
            die "Restore from ${BACKUP_DIR} or remove ${RULES_DEST}, then restart."
        fi
    else
        die "systemctl restart failed"
    fi
else
    warn "Not restarted. The rules are on disk but inactive until you run:"
    echo "        systemctl restart wazuh-manager"
fi

# ---------------------------------------------------------------------------
step "Done"
cat <<EOF

    Dashboard queries to try:

      rule.groups:suricata                      everything from this integration
      rule.id:100210                            DNS queries seen by this endpoint
      rule.id:100220                            TLS SNI -- "what sites did it visit"
      rule.id:(100200 OR 100201)                real IDS alerts, high and medium
      rule.id:100211                            possible DNS tunnelling
      data.tls.sni:*                            SNI values as a searchable field
      data.dns.rrname:*                         queried domains

    If DNS results look sparse, DNS-over-HTTPS is the usual reason -- browsers hide
    their lookups from Suricata. Run scripts\\06-disable-doh.ps1 on the endpoint.

EOF
