#!/usr/bin/env bash
# =============================================================================
# teardown.sh — Full Demo Teardown
# =============================================================================
# Stops and removes all demo resources in reverse order:
#   1. Stop application containers
#   2. Destroy Terraform-managed Vault configuration
#   3. Stop and remove Vault Enterprise container
#   4. Stop and remove MongoDB container
#   5. Optionally remove persistent data directories
#
# Usage:
#   ./scripts/teardown.sh              # Stops containers + destroys Vault config
#   ./scripts/teardown.sh --purge      # Also deletes ~/.demo/* data directories
#   ./scripts/teardown.sh --containers-only  # Only stops containers (keep config)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform"
COMPOSE_DIR="${ROOT_DIR}/nerdctl-compose"

# ─────────────────────────────────────────────────────────────────────────────
# Parse flags
# ─────────────────────────────────────────────────────────────────────────────
PURGE=false
CONTAINERS_ONLY=false

for arg in "$@"; do
  case $arg in
    --purge)           PURGE=true ;;
    --containers-only) CONTAINERS_ONLY=true ;;
    *)                 echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Color helpers
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
header()  { echo -e "\n${BOLD}════════════════════════════════════════${NC}"; echo -e "${BOLD} $*${NC}"; echo -e "${BOLD}════════════════════════════════════════${NC}"; }

# ─────────────────────────────────────────────────────────────────────────────
# Confirmation prompt
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}${BOLD}WARNING:${NC} This will stop all demo containers and destroy Vault configuration."
if [[ "${PURGE}" == "true" ]]; then
  echo -e "${RED}${BOLD}--purge is set:${NC} Vault data and MongoDB data will also be deleted permanently."
fi
echo ""
read -rp "Continue? [y/N] " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Teardown cancelled."
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Stop application containers
# ─────────────────────────────────────────────────────────────────────────────
header "Step 1: Stop Application Containers"

# Determine container runtime (nerdctl or docker)
if command -v nerdctl &>/dev/null; then
  COMPOSE_CMD="nerdctl compose"
elif command -v docker &>/dev/null; then
  COMPOSE_CMD="docker compose"
else
  warn "Neither nerdctl nor docker found — skipping container teardown"
  COMPOSE_CMD=""
fi

if [[ -n "${COMPOSE_CMD}" ]]; then
  if [[ -f "${COMPOSE_DIR}/docker-compose.yml" ]]; then
    ${COMPOSE_CMD} \
      -f "${COMPOSE_DIR}/docker-compose.yml" \
      --project-name confused-demo \
      down --remove-orphans 2>/dev/null || true
    success "Application containers stopped"
  else
    warn "Compose file not found — skipping"
  fi
fi

if [[ "${CONTAINERS_ONLY}" == "true" ]]; then
  success "Container teardown complete (--containers-only was set)"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Terraform destroy (remove Vault namespace and config)
# ─────────────────────────────────────────────────────────────────────────────
header "Step 2: Terraform Destroy (Vault Configuration)"

if [[ -f "${TERRAFORM_DIR}/terraform.tfstate" ]] || [[ -d "${TERRAFORM_DIR}/.terraform" ]]; then
  # Load Vault token for provider authentication
  VAULT_TOKEN_FILE="${HOME}/.demo/vault/.vault-token"
  if [[ -f "${VAULT_TOKEN_FILE}" ]]; then
    export VAULT_TOKEN
    VAULT_TOKEN=$(cat "${VAULT_TOKEN_FILE}")
    export VAULT_ADDR="http://127.0.0.1:8200"
    export TF_VAR_vault_token="${VAULT_TOKEN}"

    # Load mongo password
    MONGO_PASSWORD_FILE="${HOME}/.demo/mongodb/password"
    if [[ -f "${MONGO_PASSWORD_FILE}" ]]; then
      export TF_VAR_mongo_password
      TF_VAR_mongo_password=$(cat "${MONGO_PASSWORD_FILE}")
    fi

    cd "${TERRAFORM_DIR}"
    # Load tfvars for other required variables
    if [[ -f "terraform.tfvars" ]]; then
      terraform destroy -auto-approve
      success "Vault configuration destroyed"
    else
      warn "terraform.tfvars not found — skipping terraform destroy"
    fi
  else
    warn "Vault token not found — skipping Terraform destroy"
    warn "If Vault is running, you may need to manually destroy resources."
  fi
else
  info "No Terraform state found — skipping"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Stop and remove Vault container
# ─────────────────────────────────────────────────────────────────────────────
header "Step 3: Stop Vault Enterprise Container"

for RUNTIME in nerdctl docker; do
  if command -v "${RUNTIME}" &>/dev/null; then
    ${RUNTIME} stop vault-enterprise 2>/dev/null && \
      ${RUNTIME} rm vault-enterprise 2>/dev/null && \
      success "Vault container removed" || \
      info "Vault container not running"
    break
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: Stop and remove MongoDB container
# ─────────────────────────────────────────────────────────────────────────────
header "Step 4: Stop MongoDB Container"

for RUNTIME in nerdctl docker; do
  if command -v "${RUNTIME}" &>/dev/null; then
    ${RUNTIME} stop mongodb 2>/dev/null && \
      ${RUNTIME} rm mongodb 2>/dev/null && \
      success "MongoDB container removed" || \
      info "MongoDB container not running"
    break
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5: Purge data (optional)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${PURGE}" == "true" ]]; then
  header "Step 5: Purge Data Directories"

  echo -e "${RED}Deleting: ${HOME}/.demo/vault${NC}"
  rm -rf "${HOME}/.demo/vault"
  success "Vault data deleted"

  echo -e "${RED}Deleting: ${HOME}/.demo/mongodb${NC}"
  rm -rf "${HOME}/.demo/mongodb"
  success "MongoDB data deleted"

  # Remove generated .env files (they contain secrets)
  for env_file in \
    "${COMPOSE_DIR}/.env" \
    "${COMPOSE_DIR}/products-agent/.env" \
    "${COMPOSE_DIR}/products-mcp/.env" \
    "${COMPOSE_DIR}/products-web/.env"; do
    if [[ -f "${env_file}" ]]; then
      rm -f "${env_file}"
      info "Removed ${env_file}"
    fi
  done
  success "Generated .env files removed"

  # Remove Terraform state
  rm -f "${TERRAFORM_DIR}/terraform.tfstate"
  rm -f "${TERRAFORM_DIR}/terraform.tfstate.backup"
  rm -rf "${TERRAFORM_DIR}/.terraform"
  info "Terraform state cleared"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD} Teardown complete${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""
if [[ "${PURGE}" == "false" ]]; then
  echo "  Vault data preserved at ~/.demo/vault (re-use with --skip-infra)"
  echo "  MongoDB data preserved at ~/.demo/mongodb"
  echo "  To fully clean up: ./scripts/teardown.sh --purge"
fi
echo ""
