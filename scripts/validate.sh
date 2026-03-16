#!/usr/bin/env bash
# =============================================================================
# validate.sh — Demo Health Check
# =============================================================================
# Checks that all demo services are running and responding.
# Exits with code 0 if all services are healthy, 1 if any are down.
#
# Usage:
#   ./scripts/validate.sh
#   ./scripts/validate.sh --verbose   # Show full response bodies
# =============================================================================

set -euo pipefail

VERBOSE=false
for arg in "$@"; do
  [[ "$arg" == "--verbose" ]] && VERBOSE=true
done

# ─────────────────────────────────────────────────────────────────────────────
# Color helpers
# ─────────────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; }
info()  { echo -e "  ${YELLOW}→${NC} $*"; }

FAILURES=0

# ─────────────────────────────────────────────────────────────────────────────
# Helper: check HTTP endpoint
# ─────────────────────────────────────────────────────────────────────────────
check_http() {
  local name="$1"
  local url="$2"
  local expected_codes="${3:-200}"

  response=$(curl -s -o /tmp/validate_body -w "%{http_code}" \
    --connect-timeout 5 --max-time 10 "${url}" 2>/dev/null || echo "000")

  # Check if response code is in expected list
  if echo "${expected_codes}" | grep -qw "${response}"; then
    pass "${name} (${url}) — HTTP ${response}"
    if [[ "${VERBOSE}" == "true" ]]; then
      info "Response: $(cat /tmp/validate_body | head -c 200)"
    fi
  else
    fail "${name} (${url}) — HTTP ${response} (expected one of: ${expected_codes})"
    if [[ "${VERBOSE}" == "true" ]] && [[ -f /tmp/validate_body ]]; then
      info "Response: $(cat /tmp/validate_body | head -c 200)"
    fi
    ((FAILURES++)) || true
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: check TCP port
# ─────────────────────────────────────────────────────────────────────────────
check_port() {
  local name="$1"
  local host="$2"
  local port="$3"

  if nc -z -w 3 "${host}" "${port}" 2>/dev/null; then
    pass "${name} — listening on ${host}:${port}"
  else
    fail "${name} — not reachable on ${host}:${port}"
    ((FAILURES++)) || true
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Run checks
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Vault Agentic IAM — Service Health Check${NC}"
echo "════════════════════════════════════════"
echo ""

echo -e "${BOLD}Infrastructure${NC}"
# Vault health endpoint: 200=active, 503=sealed, 501=uninitialised
check_http "Vault" "http://127.0.0.1:8200/v1/sys/health" "200 429 472 473"
check_port "MongoDB" "127.0.0.1" "27017"

echo ""
echo -e "${BOLD}Application Services${NC}"
# MCP server — any 2xx or 4xx means it's running
check_http "products-mcp" "http://127.0.0.1:8000" "200 404 405 422"
# Agent API — same logic
check_http "products-agent" "http://127.0.0.1:8001" "200 404 405 422"
# Streamlit UI — 200 or 302 (redirect to login)
check_http "products-web" "http://127.0.0.1:8501" "200 302"

echo ""
echo -e "${BOLD}Container Status${NC}"
# List running containers for quick visual confirmation
if command -v nerdctl &>/dev/null; then
  nerdctl ps --format "  {{.Names}}\t{{.Status}}" 2>/dev/null | grep -E "vault|mongo|products" | while IFS= read -r line; do
    echo -e "  ${YELLOW}→${NC} ${line}"
  done
elif command -v docker &>/dev/null; then
  docker ps --format "  {{.Names}}\t{{.Status}}" 2>/dev/null | grep -E "vault|mongo|products" | while IFS= read -r line; do
    echo -e "  ${YELLOW}→${NC} ${line}"
  done
fi

# ─────────────────────────────────────────────────────────────────────────────
# Result
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
if [[ "${FAILURES}" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}All services healthy${NC}"
  echo ""
  echo "  Open the demo: http://localhost:8501"
  exit 0
else
  echo -e "${RED}${BOLD}${FAILURES} service(s) failed health check${NC}"
  echo ""
  echo "  Troubleshooting:"
  echo "    nerdctl ps -a                                    # Check container status"
  echo "    nerdctl logs vault-enterprise                    # Vault logs"
  echo "    nerdctl logs mongodb                             # MongoDB logs"
  echo "    nerdctl compose -f nerdctl-compose/docker-compose.yml logs  # App logs"
  exit 1
fi
