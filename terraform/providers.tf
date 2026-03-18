# =============================================================================
# providers.tf — Provider Configuration
# =============================================================================
# Configures the Vault provider to connect to the locally running Vault
# Enterprise container. Token authentication is used (root token generated
# during `ansible-playbook 02-vault.yml`).
#
# The namespace "admin" is the root enterprise namespace — all demo resources
# are created inside a child namespace (see main.tf) to isolate them and
# demonstrate Vault namespace-based multi-tenancy.
# =============================================================================

provider "vault" {
  # Address of the local Vault Enterprise container (started by Ansible)
  address = var.vault_addr

  # Root token from: cat ~/.demo/vault/.vault-token
  # Set via terraform.tfvars or TF_VAR_vault_token environment variable
  token = var.vault_token

  # "admin" is the root enterprise namespace — child namespaces are created
  # under it. All vault_* resources that specify namespace = ... will operate
  # within the demo child namespace.
  namespace = "admin"
}

# Root-level Vault provider (no namespace).
# Required for resources that are not namespace-scoped in Vault Enterprise:
#   - vault_audit (audit devices are global, not per-namespace)
# Usage: add `provider = vault.root` to any such resource.
provider "vault" {
  alias   = "root"
  address = var.vault_addr
  token   = var.vault_token
  # No namespace — operates at the root of Vault
}
