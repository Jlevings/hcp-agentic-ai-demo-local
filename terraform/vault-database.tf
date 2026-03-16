# =============================================================================
# vault-database.tf — Dynamic MongoDB Secrets Engine
# =============================================================================
# Configures Vault's database secrets engine to generate short-lived,
# ephemeral MongoDB credentials on demand.
#
# How it works:
#   1. The MCP server authenticates to Vault (JWT auth) and receives a token
#   2. It calls `vault read database/creds/<role>` using that token
#   3. Vault connects to MongoDB as the admin user and creates a new user
#      with the appropriate role (read or readWrite on the test database)
#   4. Vault returns the ephemeral username/password to the MCP server
#   5. After TTL expiry, Vault revokes the MongoDB user automatically
#
# This eliminates long-lived database credentials entirely — the core of
# the Vault Agentic IAM demo's security story.
# =============================================================================

# Mount the database secrets engine at the "database" path.
# This is the engine that manages dynamic credential generation for MongoDB.
resource "vault_mount" "database" {
  namespace   = local.namespace
  path        = "database"
  type        = "database"
  description = "Dynamic MongoDB credentials for the products demo database"
}

# Configure the MongoDB connection that Vault uses to create/revoke users.
# The admin credentials (mongoadmin) are stored securely in Vault and never
# exposed to the application — applications only ever see the ephemeral creds.
#
# host.docker.internal resolves to the host machine from inside a container,
# allowing the app containers to reach MongoDB running on the host (or in
# another container on the host network).
resource "vault_database_secret_backend_connection" "mongodb" {
  namespace = local.namespace
  backend   = vault_mount.database.path
  name      = "mongodb"

  # These are the roles that can request credentials from this connection.
  # Vault enforces that only these named roles can use this backend connection.
  allowed_roles = ["readonly", "readwrite"]

  mongodb {
    # connection_url uses template syntax — {{username}} and {{password}} are
    # replaced by Vault with the admin credentials at runtime (never hardcoded
    # in the URL itself — Vault substitutes them from the username/password fields)
    connection_url = "mongodb://{{username}}:{{password}}@host.docker.internal:27017/admin"

    # The admin account Vault uses to create/revoke ephemeral users
    username = var.mongo_username
    password = var.mongo_password
  }
}

# Read-only database role — generates MongoDB users with read access on the test DB.
# Used by Alice (member of db-readonly Entra ID group → readonly Vault policy).
resource "vault_database_secret_backend_role" "readonly" {
  namespace = local.namespace
  backend   = vault_mount.database.path
  name      = "readonly"

  # References the connection configured above
  db_name = vault_database_secret_backend_connection.mongodb.name

  # MongoDB command to create the ephemeral user.
  # Grants the built-in `read` role on the `test` database only.
  creation_statements = [
    "{\"db\": \"admin\", \"roles\": [{\"role\": \"read\", \"db\": \"test\"}]}"
  ]

  # Credentials expire after 5 minutes — forces re-authentication per request.
  # This keeps the blast radius minimal if a credential is ever intercepted.
  default_ttl = 300  # 5 minutes in seconds
  max_ttl     = 600  # 10 minutes absolute maximum
}

# Read-write database role — generates MongoDB users with readWrite access on the test DB.
# Used by Bob (member of db-readwrite Entra ID group → readwrite Vault policy).
resource "vault_database_secret_backend_role" "readwrite" {
  namespace = local.namespace
  backend   = vault_mount.database.path
  name      = "readwrite"

  db_name = vault_database_secret_backend_connection.mongodb.name

  # Grants the built-in `readWrite` role on the `test` database.
  # This allows Bob to both read and write product records.
  creation_statements = [
    "{\"db\": \"admin\", \"roles\": [{\"role\": \"readWrite\", \"db\": \"test\"}]}"
  ]

  default_ttl = 300  # 5 minutes
  max_ttl     = 600  # 10 minutes
}
