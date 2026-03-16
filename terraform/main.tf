# =============================================================================
# main.tf — Vault Namespace
# =============================================================================
# Creates the demo Vault namespace with a unique suffix.
# All other resources (auth, policies, secrets) are scoped to this namespace,
# keeping the demo isolated from any other Vault configuration.
#
# A random suffix prevents naming collisions if the demo is deployed multiple
# times or alongside other namespaces.
# =============================================================================

# Generate a random 4-character suffix for the namespace name.
# This ensures uniqueness across multiple demo deployments on the same Vault.
resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

# Create the demo namespace under the "admin" root enterprise namespace.
# The Vault provider is configured with namespace = "admin" in providers.tf,
# so this resource creates a child namespace: admin/agentic-iam-<suffix>
resource "vault_namespace" "demo" {
  path = "agentic-iam-${random_string.suffix.result}"
}
