# =============================================================================
# vault-auth.tf — Vault JWT Auth, Policies, and Identity Groups
# =============================================================================
# This file configures the identity and authorization layer in Vault:
#
#   1. Policies — what database credential paths each role can read
#   2. JWT Auth Backend — validates Entra ID tokens (OBO tokens from the agent)
#   3. JWT Auth Role — maps token claims to Vault entities
#   4. Identity Groups — external groups that map Entra ID security groups
#      to Vault policies via the `groups` claim in the JWT
#   5. Group Aliases — link each Entra ID group Object ID to a Vault group
#
# Security model:
#   - The MCP server receives an OBO token from the agent
#   - It presents that token to Vault's JWT auth endpoint
#   - Vault validates the token against Entra ID's JWKS endpoint
#   - The `groups` claim contains the user's Entra ID group Object IDs
#   - Vault maps those Object IDs to identity group aliases
#   - The matching group's policy is applied — readonly or readwrite
# =============================================================================

locals {
  # The demo namespace path (relative to the "admin" parent namespace)
  # Used on all resources scoped to the demo namespace
  namespace = vault_namespace.demo.path
}

# ── Policies ──────────────────────────────────────────────────────────────────

# Read-only policy — grants permission to generate ephemeral MongoDB read credentials.
# Assigned to users in the db-readonly Entra ID group (Alice).
resource "vault_policy" "readonly" {
  namespace = local.namespace
  name      = "readonly"

  policy = <<-EOT
    # Allow reading (generating) dynamic read-only MongoDB credentials
    path "database/creds/readonly" {
      capabilities = ["read"]
    }
  EOT
}

# Read-write policy — grants permission to generate ephemeral MongoDB read-write credentials.
# Assigned to users in the db-readwrite Entra ID group (Bob).
resource "vault_policy" "readwrite" {
  namespace = local.namespace
  name      = "readwrite"

  policy = <<-EOT
    # Allow reading (generating) dynamic read-write MongoDB credentials
    path "database/creds/readwrite" {
      capabilities = ["read"]
    }
  EOT
}

# ── JWT Auth Backend ──────────────────────────────────────────────────────────

# Mount the JWT auth method at the "jwt" path inside the demo namespace.
# Configured to validate tokens issued by Microsoft Entra ID for this tenant.
# The OIDC discovery URL tells Vault where to fetch the JWKS (public keys)
# used to verify token signatures.
resource "vault_jwt_auth_backend" "entra" {
  namespace = local.namespace

  description = "JWT auth backend — validates Entra ID OBO tokens from products-agent"
  path        = "jwt"

  # Entra ID's OIDC discovery URL for this tenant.
  # We use the v2.0 endpoint to get the JWKS URI (public keys for signature verification).
  # NOTE: The JWKS keys are the same for both v1 and v2 tokens.
  oidc_discovery_url = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"

  # Accept v1 access tokens — the default when app registrations have
  # accessTokenAcceptedVersion = null in their manifest.
  # v1 tokens carry iss = https://sts.windows.net/<tenant_id>/
  # v2 tokens carry iss = https://login.microsoftonline.com/<tenant_id>/v2.0
  #
  # To switch to v2 tokens (preferred for new deployments):
  #   1. In Azure Portal, set accessTokenAcceptedVersion = 2 in the
  #      products-agent and products-mcp app registration manifests.
  #   2. Update this bound_issuer to:
  #        "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
  #   3. Update JWT_ISSUER in products-agent/.env and products-mcp/.env to match.
  bound_issuer = "https://sts.windows.net/${var.tenant_id}/"
}

# ── JWT Auth Role ─────────────────────────────────────────────────────────────

# The "default" role is the single role used for all MCP server authentications.
# It validates that the token was issued for the MCP application (bound_audiences)
# and extracts the user identity and group memberships from the JWT claims.
resource "vault_jwt_auth_backend_role" "default" {
  namespace = local.namespace
  backend   = vault_jwt_auth_backend.entra.path
  role_name = "default"
  role_type = "jwt"

  # The `aud` claim in the JWT must contain the MCP App ID URI.
  # v1 access tokens use the App ID URI (api://<client_id>) as the audience,
  # not the bare GUID. v2 tokens use the bare GUID.
  # If you switch to v2 tokens (accessTokenAcceptedVersion=2 in the manifest),
  # change this back to: [var.mcp_client_id]
  bound_audiences = ["api://${var.mcp_client_id}"]

  # Use the user's Entra ID UPN as the Vault entity alias name.
  # v1 tokens use "unique_name" for the UPN; v2 tokens use "preferred_username".
  # Since app registrations default to v1 tokens (accessTokenAcceptedVersion=null),
  # we use "unique_name" here.
  user_claim = "unique_name"

  # The `groups` claim contains the user's Entra ID security group Object IDs.
  # Vault uses this to match identity group aliases (configured below).
  groups_claim = "groups"

  # Enable verbose OIDC logging for demo/debugging purposes.
  # Shows full claim sets in Vault logs — disable in production.
  verbose_oidc_logging = true

  # Map additional JWT claims into Vault entity metadata for audit visibility
  claim_mappings = {
    "name" = "name"
    "aud"  = "aud"
  }
}

# ── External Identity Groups ──────────────────────────────────────────────────
# External groups are managed outside Vault (by the identity provider).
# Vault doesn't control group membership — Entra ID does via the JWT `groups` claim.
# Each external group is linked to a policy that grants the appropriate DB access.

# Readonly identity group — linked to the readonly policy.
# Members: anyone whose JWT contains the db-readonly group Object ID.
resource "vault_identity_group" "readonly" {
  namespace = local.namespace
  name      = "readonly"
  type      = "external"
  policies  = [vault_policy.readonly.name]

  metadata = {
    description = "Maps db-readonly Entra ID group to Vault readonly policy"
  }
}

# Readwrite identity group — linked to the readwrite policy.
# Members: anyone whose JWT contains the db-readwrite group Object ID.
resource "vault_identity_group" "readwrite" {
  namespace = local.namespace
  name      = "readwrite"
  type      = "external"
  policies  = [vault_policy.readwrite.name]

  metadata = {
    description = "Maps db-readwrite Entra ID group to Vault readwrite policy"
  }
}

# ── Group Aliases ─────────────────────────────────────────────────────────────
# Aliases connect the JWT auth backend to the identity groups.
# The alias `name` must match the value that appears in the JWT `groups` claim,
# which for Entra ID security groups is the group's Object ID (a GUID).

# Alias for the readonly group — name = Entra ID db-readonly group Object ID
resource "vault_identity_group_alias" "readonly" {
  namespace = local.namespace

  # The Entra ID group Object ID that appears in the JWT groups claim
  name = var.readonly_group_object_id

  # The JWT auth backend accessor — links the alias to the correct auth method
  mount_accessor = vault_jwt_auth_backend.entra.accessor

  # The Vault identity group this alias maps to
  canonical_id = vault_identity_group.readonly.id
}

# Alias for the readwrite group — name = Entra ID db-readwrite group Object ID
resource "vault_identity_group_alias" "readwrite" {
  namespace = local.namespace

  name           = var.readwrite_group_object_id
  mount_accessor = vault_jwt_auth_backend.entra.accessor
  canonical_id   = vault_identity_group.readwrite.id
}

# ── Audit Logging ─────────────────────────────────────────────────────────────
# Enable Vault's file audit device so every request and response is recorded
# as newline-delimited JSON at /vault/logs/audit.log inside the container.
# The host directory ~/.demo/vault/logs is mounted at /vault/logs in the
# vault-enterprise container (see nerdctl-compose/docker-compose.yml), making
# the log readable from the host and from the vault-observer container.
#
# Audit devices are root-level resources — they are NOT namespace-scoped.
# This means the provider must authenticate at root, which it does via
# vault_token in providers.tf (no namespace attribute here).
#
# Each log entry contains:
#   time           — ISO8601 timestamp of the event
#   type           — "request" or "response"
#   auth           — who authenticated (display_name, policies, entity_id, token_ttl)
#   request.path   — which Vault API path was called (e.g. auth/jwt/login)
#   response.data  — returned data (e.g. DB username, lease_duration for creds)
#
# To view logs from the host:
#   cat ~/.demo/vault/logs/audit.log | python3 -m json.tool
# To tail live during a demo:
#   tail -f ~/.demo/vault/logs/audit.log
resource "vault_audit" "file" {
  # Audit devices are root-level in Vault Enterprise — they are NOT namespace-scoped.
  # Use the root provider alias (no namespace) so Vault accepts the request.
  provider = vault.root

  type = "file"

  options = {
    # Path inside the vault-enterprise container — maps to ~/.demo/vault/logs on host
    file_path = "/vault/logs/audit.log"
  }
}
