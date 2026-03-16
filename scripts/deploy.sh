#!/usr/bin/env bash
# =============================================================================
# deploy.sh — One-Command Demo Deployment
# =============================================================================
# Orchestrates the full demo deployment in the correct order:
#   1. Check prerequisites
#   2. Load environment variables from .env file
#   3. Start Vault Enterprise (Ansible)
#   4. Start MongoDB (Ansible)
#   5. Configure Vault (Terraform)
#   6. Start application containers (Ansible)
#   7. Validate all services
#   8. Print access information
#
# Usage:
#   ./scripts/deploy.sh [--skip-prereqs] [--skip-infra] [--skip-terraform]
#
#   --skip-prereqs   Skip the prerequisites check (faster if already verified)
#   --skip-infra     Skip Vault and MongoDB setup (if already running)
#   --skip-terraform Skip Terraform apply (if Vault is already configured)
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Script directory and paths
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_DIR="${ROOT_DIR}/ansible"
TERRAFORM_DIR="${ROOT_DIR}/terraform"
COMPOSE_DIR="${ROOT_DIR}/nerdctl-compose"
ENV_FILE="${COMPOSE_DIR}/.env"
ENV_EXAMPLE="${COMPOSE_DIR}/.env.example"

# ─────────────────────────────────────────────────────────────────────────────
# Parse flags
# ─────────────────────────────────────────────────────────────────────────────
SKIP_PREREQS=false
SKIP_INFRA=false
SKIP_TERRAFORM=false

for arg in "$@"; do
  case $arg in
    --skip-prereqs)   SKIP_PREREQS=true ;;
    --skip-infra)     SKIP_INFRA=true ;;
    --skip-terraform) SKIP_TERRAFORM=true ;;
    *)                echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Color output helpers
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}════════════════════════════════════════${NC}"; echo -e "${BOLD} $*${NC}"; echo -e "${BOLD}════════════════════════════════════════${NC}"; }

# ─────────────────────────────────────────────────────────────────────────────
# STEP 0: Check .env file exists
# ─────────────────────────────────────────────────────────────────────────────
header "Step 0: Environment Setup"

if [[ ! -f "${ENV_FILE}" ]]; then
  warn ".env file not found at ${ENV_FILE}"
  info "Copying .env.example → .env"
  cp "${ENV_EXAMPLE}" "${ENV_FILE}"
  echo ""
  echo -e "${YELLOW}ACTION REQUIRED:${NC}"
  echo "  Please fill in all values in: ${ENV_FILE}"
  echo "  Then re-run this script."
  echo ""
  echo "  Refer to docs/ENTRA-ID-SETUP.md for Azure credential setup."
  exit 1
fi

# Load environment variables from .env file
# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a
success ".env loaded from ${ENV_FILE}"

# Validate critical variables are set
REQUIRED_VARS=(TENANT_ID WEB_CLIENT_ID WEB_CLIENT_SECRET AGENT_CLIENT_ID AGENT_CLIENT_SECRET MCP_CLIENT_ID)
MISSING=()
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    MISSING+=("$var")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  error "Required variables not set in ${ENV_FILE}:\n  ${MISSING[*]}\n\nSee docs/ENTRA-ID-SETUP.md for instructions."
fi

# Validate LLM backend
if [[ -z "${BEDROCK_INFERENCE_PROFILE_ARN:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  error "No LLM backend configured.\nSet either BEDROCK_INFERENCE_PROFILE_ARN or ANTHROPIC_API_KEY in ${ENV_FILE}"
fi
success "All required environment variables are set"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Prerequisites
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_PREREQS}" == "false" ]]; then
  header "Step 1: Prerequisites"
  cd "${ANSIBLE_DIR}"
  ansible-playbook playbooks/01-prerequisites.yml
  success "Prerequisites satisfied"
else
  info "Skipping prerequisites check (--skip-prereqs)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Start Vault Enterprise
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_INFRA}" == "false" ]]; then
  header "Step 2: Start Vault Enterprise"
  cd "${ANSIBLE_DIR}"
  ansible-playbook playbooks/02-vault.yml
  success "Vault Enterprise is running"

  # Export root token for Terraform
  export VAULT_TOKEN
  VAULT_TOKEN=$(cat "${HOME}/.demo/vault/.vault-token")
  export VAULT_ADDR="http://127.0.0.1:8200"
else
  info "Skipping infrastructure setup (--skip-infra)"
  VAULT_TOKEN=$(cat "${HOME}/.demo/vault/.vault-token" 2>/dev/null || echo "")
  if [[ -z "${VAULT_TOKEN}" ]]; then
    error "Vault token not found. Run without --skip-infra first."
  fi
  export VAULT_TOKEN
  export VAULT_ADDR="http://127.0.0.1:8200"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Start MongoDB
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_INFRA}" == "false" ]]; then
  header "Step 3: Start MongoDB"
  cd "${ANSIBLE_DIR}"
  ansible-playbook playbooks/03-mongodb.yml
  success "MongoDB is running"

  # Load MongoDB password for Terraform
  MONGO_PASSWORD=$(cat "${HOME}/.demo/mongodb/password")
  export TF_VAR_mongo_password="${MONGO_PASSWORD}"
else
  info "Skipping MongoDB setup (--skip-infra)"
  MONGO_PASSWORD=$(cat "${HOME}/.demo/mongodb/password" 2>/dev/null || echo "")
  if [[ -z "${MONGO_PASSWORD}" ]]; then
    error "MongoDB password not found. Run without --skip-infra first."
  fi
  export TF_VAR_mongo_password="${MONGO_PASSWORD}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: Terraform — Configure Vault
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_TERRAFORM}" == "false" ]]; then
  header "Step 4: Configure Vault (Terraform)"
  cd "${TERRAFORM_DIR}"

  # Check if terraform.tfvars exists
  if [[ ! -f "terraform.tfvars" ]]; then
    warn "terraform.tfvars not found — copying from example"
    cp terraform.tfvars.example terraform.tfvars
    warn "Please edit terraform/terraform.tfvars with your values, then re-run."
    exit 1
  fi

  # Set sensitive vars from environment so they don't have to be in tfvars
  export TF_VAR_vault_token="${VAULT_TOKEN}"
  export TF_VAR_agent_client_secret="${AGENT_CLIENT_SECRET}"
  export TF_VAR_web_client_secret="${WEB_CLIENT_SECRET}"

  info "Running terraform init..."
  terraform init -upgrade

  info "Running terraform apply..."
  terraform apply -auto-approve

  # Read the Vault namespace from Terraform output
  VAULT_NAMESPACE=$(terraform output -raw vault_namespace)
  export VAULT_NAMESPACE
  success "Vault configured. Namespace: ${VAULT_NAMESPACE}"

  # Persist VAULT_NAMESPACE to .env for subsequent runs
  if grep -q "^VAULT_NAMESPACE=" "${ENV_FILE}"; then
    sed -i '' "s|^VAULT_NAMESPACE=.*|VAULT_NAMESPACE=${VAULT_NAMESPACE}|" "${ENV_FILE}"
  else
    echo "VAULT_NAMESPACE=${VAULT_NAMESPACE}" >> "${ENV_FILE}"
  fi
else
  info "Skipping Terraform (--skip-terraform)"
  VAULT_NAMESPACE="${VAULT_NAMESPACE:-}"
  if [[ -z "${VAULT_NAMESPACE}" ]]; then
    VAULT_NAMESPACE=$(cd "${TERRAFORM_DIR}" && terraform output -raw vault_namespace 2>/dev/null || echo "")
  fi
  if [[ -z "${VAULT_NAMESPACE}" ]]; then
    error "VAULT_NAMESPACE not set. Run without --skip-terraform first."
  fi
  export VAULT_NAMESPACE
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5: Start Application Containers
# ─────────────────────────────────────────────────────────────────────────────
header "Step 5: Start Application Containers"
cd "${ANSIBLE_DIR}"

# Export all required vars for the Ansible app-stack playbook
export TENANT_ID WEB_CLIENT_ID WEB_CLIENT_SECRET AGENT_CLIENT_ID AGENT_CLIENT_SECRET
export MCP_CLIENT_ID WEB_SCOPES AGENT_SCOPES REDIRECT_URI VAULT_NAMESPACE
export BEDROCK_INFERENCE_PROFILE_ARN BEDROCK_REGION ANTHROPIC_API_KEY

ansible-playbook playbooks/04-app-stack.yml
success "Application containers are running"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6: Validate
# ─────────────────────────────────────────────────────────────────────────────
header "Step 6: Validation"
"${SCRIPT_DIR}/validate.sh" || warn "Some services may still be starting — wait 30s and run ./scripts/validate.sh"

# ─────────────────────────────────────────────────────────────────────────────
# SUCCESS
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD} Demo is ready!${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Web App:${NC}       http://localhost:8501"
echo -e "  ${BOLD}Vault UI:${NC}      http://localhost:8200/ui"
echo -e "  ${BOLD}Agent API:${NC}     http://localhost:8001"
echo -e "  ${BOLD}MCP Server:${NC}    http://localhost:8000"
echo ""
echo -e "  ${BOLD}Alice (read-only):${NC} ${ALICE_USERNAME:-<set ALICE_USERNAME in .env>}"
echo -e "  ${BOLD}Bob (read-write):${NC}  ${BOB_USERNAME:-<set BOB_USERNAME in .env>}"
echo ""
echo -e "  See ${BOLD}docs/TEST.md${NC} for the demo talk track and test steps."
echo -e "  To tear down: ${BOLD}./scripts/teardown.sh${NC}"
echo ""
