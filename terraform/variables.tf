# =============================================================================
# variables.tf — Input Variable Declarations
# =============================================================================
# All variables used across the Terraform configuration.
# Values are supplied via terraform.tfvars (gitignored).
# Sensitive variables are marked sensitive = true to suppress log output.
# =============================================================================

# ── Vault Connection ──────────────────────────────────────────────────────────

variable "vault_addr" {
  description = "Address of the local Vault Enterprise instance"
  type        = string
  default     = "http://127.0.0.1:8200"
}

variable "vault_token" {
  description = "Vault root token — obtained after running ansible/playbooks/02-vault.yml (cat ~/.demo/vault/.vault-token)"
  type        = string
  sensitive   = true
}

# ── Microsoft Entra ID ────────────────────────────────────────────────────────

variable "tenant_id" {
  description = "Microsoft Entra ID tenant ID (Azure Portal > Entra ID > Overview)"
  type        = string
}

variable "mcp_client_id" {
  description = "App registration client ID for products-mcp (the MCP server). Used as the JWT audience that Vault validates."
  type        = string
}

variable "agent_client_id" {
  description = "App registration client ID for products-agent (the Agent API). Performs OBO token exchange."
  type        = string
}

variable "agent_client_secret" {
  description = "Client secret for products-agent app registration"
  type        = string
  sensitive   = true
}

variable "web_client_id" {
  description = "App registration client ID for products-web (the Streamlit frontend). Users log in through this app."
  type        = string
}

variable "web_client_secret" {
  description = "Client secret for products-web app registration"
  type        = string
  sensitive   = true
}

# ── Entra ID Security Group Object IDs ───────────────────────────────────────
# These Object IDs are what Entra ID puts in the JWT `groups` claim.
# Vault reads that claim and maps each group to an identity group alias,
# which then grants the corresponding policy (readonly or readwrite).

variable "readonly_group_object_id" {
  description = "Object ID of the db-readonly Entra ID security group (Alice's group)"
  type        = string
}

variable "readwrite_group_object_id" {
  description = "Object ID of the db-readwrite Entra ID security group (Bob's group)"
  type        = string
}

# ── OAuth Scopes ──────────────────────────────────────────────────────────────

variable "web_scopes" {
  description = "OAuth scopes requested by products-web (openid profile email + agent API scope)"
  type        = string
  default     = "openid profile email"
}

variable "agent_scopes" {
  description = "OAuth scope for OBO exchange — the MCP API scope"
  type        = string
}

variable "mcp_scopes" {
  description = "Scope exposed by products-mcp (used as JWT audience in Vault JWT role)"
  type        = string
}

# ── Demo Users ────────────────────────────────────────────────────────────────

variable "alice_username" {
  description = "Alice's Entra ID UPN (read-only user)"
  type        = string
}

variable "alice_password" {
  description = "Alice's Entra ID password"
  type        = string
  sensitive   = true
}

variable "bob_username" {
  description = "Bob's Entra ID UPN (read-write user)"
  type        = string
}

variable "bob_password" {
  description = "Bob's Entra ID password"
  type        = string
  sensitive   = true
}

# ── MongoDB ───────────────────────────────────────────────────────────────────

variable "mongo_username" {
  description = "MongoDB admin username (created by Ansible playbook 03-mongodb.yml)"
  type        = string
  default     = "mongoadmin"
}

variable "mongo_password" {
  description = "MongoDB admin password — obtained after running ansible/playbooks/03-mongodb.yml (cat ~/.demo/mongodb/password)"
  type        = string
  sensitive   = true
}

# ── Redirect URI ──────────────────────────────────────────────────────────────

variable "redirect_uri" {
  description = "OAuth redirect URI for the Streamlit web app"
  type        = string
  default     = "http://localhost:8501/callback"
}

# ── LLM Backend ───────────────────────────────────────────────────────────────

variable "bedrock_region" {
  description = "AWS region for Bedrock inference (used if bedrock_inference_profile_arn is set)"
  type        = string
  default     = "us-west-2"
}

variable "bedrock_inference_profile_arn" {
  description = "AWS Bedrock inference profile ARN — leave empty to use Anthropic API instead"
  type        = string
  default     = ""
}

variable "anthropic_api_key" {
  description = "Anthropic API key — used if bedrock_inference_profile_arn is empty"
  type        = string
  sensitive   = true
  default     = ""
}
