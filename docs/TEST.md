# Demo Test Guide

How to run and validate the Vault Agentic IAM demo after deployment.

---

## Pre-Demo Checklist

Before presenting the demo, verify:

```bash
./scripts/validate.sh
```

All services should show ✓. Then open http://localhost:8501 and sign in as
Alice to confirm the end-to-end flow works before going live.

---

## Demo Flow

### Sign In as Alice (Read-Only User)

1. Open http://localhost:8501 in an **incognito/private window**
2. Click the login button
3. Sign in with Alice's credentials:
   - Username: `alice@yourtenant.onmicrosoft.com`
   - Password: (from `ALICE_PASSWORD` in your `.env`)
4. Complete MFA if prompted
5. You should see the chat interface

**Test read operation:**
```
List all products
```
Expected: A list of products appears (8 items seeded during setup).

> **Note:** If no products appear on the first try, run the query again.
> This is a known behavior of the initialization message.

**Test write operation (should FAIL):**
```
Add a new product named "Chair Model X" with price $49.99
```
Expected: An error message — Alice does not have write permission.

This proves Vault enforced Alice's read-only policy from her Entra ID group membership.

---

### Sign In as Bob (Read-Write User)

1. Open a **new incognito window** (don't reuse Alice's session)
2. Navigate to http://localhost:8501
3. Sign in with Bob's credentials:
   - Username: `bob@yourtenant.onmicrosoft.com`
   - Password: (from `BOB_PASSWORD` in your `.env`)
4. Complete MFA if prompted

**Test read operation:**
```
List all products
```
Expected: Product list appears.

**Test write operation (should SUCCEED):**
```
Add a new product named "Table Model Y" with price $89.99
```
Expected: Confirmation message — product was added.

**Verify product was added (still as Bob):**
```
List all products
```
Expected: "Table Model Y" now appears in the list.

---

## Verify Vault Issued Dynamic Credentials

To demonstrate that Vault issued short-lived credentials:

1. Sign into the Vault UI: http://localhost:8200/ui
2. Log in with the root token: `cat ~/.demo/vault/.vault-token`
3. Navigate to: **Secrets → database → creds → readonly** (or readwrite)
4. Click **Generate** to see a credential (or check what was last issued)
5. Notice the **Lease Duration** — credentials expire in 5 minutes

Alternatively, via CLI:
```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(cat ~/.demo/vault/.vault-token)
NAMESPACE=$(cd terraform && terraform output -raw vault_namespace)

# Generate a readonly credential (as Alice would receive)
vault read -namespace="${NAMESPACE}" database/creds/readonly

# Generate a readwrite credential (as Bob would receive)
vault read -namespace="${NAMESPACE}" database/creds/readwrite
```

Each call generates a unique username/password pair that expires in 5 minutes.

---

## Verify Identity Group Mapping

Show how Vault maps Entra ID group membership to policies:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(cat ~/.demo/vault/.vault-token)
NAMESPACE=$(cd terraform && terraform output -raw vault_namespace)

# List identity groups
vault list -namespace="${NAMESPACE}" identity/group/name

# Inspect the readonly group
vault read -namespace="${NAMESPACE}" identity/group/name/readonly

# Inspect the readwrite group
vault read -namespace="${NAMESPACE}" identity/group/name/readwrite
```

---

## Automated Smoke Test

```bash
./scripts/validate.sh --verbose
```

This checks:
- Vault health endpoint
- MongoDB TCP connectivity
- products-mcp HTTP response
- products-agent HTTP response
- products-web HTTP response

---

## View Logs

```bash
# All application containers
nerdctl compose -f nerdctl-compose/docker-compose.yml logs -f

# Single service
nerdctl logs products-mcp --follow
nerdctl logs products-agent --follow
nerdctl logs products-web --follow
nerdctl logs vault-enterprise --follow
nerdctl logs mongodb --follow
```

---

## Common Test Failures

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Login page doesn't load | products-web container down | `nerdctl logs products-web` |
| Login redirects to error | Redirect URI mismatch | Verify `REDIRECT_URI` in Azure app reg |
| "List all products" returns empty | First-run initialization | Run query a second time |
| Write fails for Bob | JWT group claim issue | Check Azure group Object IDs in `.env` |
| Write fails for Alice | Working as intended! | This is the demo proving policy enforcement |
| Vault JWT auth error | Wrong `MCP_CLIENT_ID` | Verify `MCP_CLIENT_ID` vs app registration |
| Agent returns 500 | Bedrock/Anthropic config | Check LLM credentials in `.env` |
