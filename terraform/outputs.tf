# =============================================================================
# outputs.tf — Terraform Outputs
# =============================================================================
# Outputs are used by deploy.sh to:
#   - Set VAULT_NAMESPACE in the nerdctl-compose .env file
#   - Display connection information after a successful apply
#   - Provide values the Ansible app-stack role needs for container env vars
# =============================================================================

# The full namespace path as Vault sees it (relative to the admin parent).
# deploy.sh captures this with: terraform output -raw vault_namespace
# and writes it to nerdctl-compose/.env as VAULT_NAMESPACE.
output "vault_namespace" {
  description = "Full Vault namespace path including admin parent (used in container VAULT_NAMESPACE env var)"
  # Vault resources are created under the 'admin' parent namespace (set in providers.tf).
  # Containers must use the full path 'admin/<demo_namespace>' in X-Vault-Namespace headers.
  value       = "admin/${vault_namespace.demo.path}"
}

# The Vault address that containers use to reach Vault.
# Now that Vault runs inside the compose network, containers reach it by service name.
output "vault_addr_for_containers" {
  description = "Vault address as reachable from inside Docker/nerdctl containers"
  value       = "http://vault-enterprise:8200"
}

# The local Vault address for CLI use
output "vault_addr_local" {
  description = "Vault address for local CLI access"
  value       = var.vault_addr
}

# Web UI URL
output "app_url" {
  description = "URL for the Streamlit web UI"
  value       = "http://localhost:8501"
}

# MCP server URL
output "mcp_url" {
  description = "URL for the products-mcp server"
  value       = "http://localhost:8000"
}

# Agent API URL
output "agent_url" {
  description = "URL for the products-agent API"
  value       = "http://localhost:8001"
}

# Demo user summary (non-sensitive)
output "demo_users" {
  description = "Demo user accounts for testing"
  value = {
    alice = {
      username = var.alice_username
      role     = "read-only (db-readonly group)"
    }
    bob = {
      username = var.bob_username
      role     = "read-write (db-readwrite group)"
    }
  }
}
