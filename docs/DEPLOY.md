# Deployment Guide

Step-by-step instructions for deploying the Vault Agentic IAM demo locally.

---

## Quick Deploy (Automated)

If you've completed prerequisites and Entra ID setup, run:

```bash
./scripts/deploy.sh
```

This single command handles everything. Continue reading for the manual
step-by-step approach or troubleshooting.

---

## Manual Step-by-Step Deployment

### Step 1: Prerequisites

```bash
ansible-playbook ansible/playbooks/01-prerequisites.yml
```

Expected output: All checks pass in green. If anything fails, see [PREREQUISITES.md](./PREREQUISITES.md).

---

### Step 2: Configure Environment Variables

```bash
cp nerdctl-compose/.env.example nerdctl-compose/.env
```

Edit `nerdctl-compose/.env` and fill in all values:

```bash
# Minimum required:
TENANT_ID=<your-azure-tenant-id>
WEB_CLIENT_ID=<products-web-client-id>
WEB_CLIENT_SECRET=<products-web-secret>
AGENT_CLIENT_ID=<products-agent-client-id>
AGENT_CLIENT_SECRET=<products-agent-secret>
MCP_CLIENT_ID=<products-mcp-client-id>
READONLY_GROUP_OBJECT_ID=<db-readonly-group-object-id>
READWRITE_GROUP_OBJECT_ID=<db-readwrite-group-object-id>
WEB_SCOPES=openid profile email api://<AGENT_CLIENT_ID>/access
AGENT_SCOPES=api://<MCP_CLIENT_ID>/access
REDIRECT_URI=http://localhost:8501/callback

# LLM — choose one:
BEDROCK_INFERENCE_PROFILE_ARN=<arn>    # Option A: AWS Bedrock
ANTHROPIC_API_KEY=<key>                # Option B: Anthropic API
```

See [ENTRA-ID-SETUP.md](./ENTRA-ID-SETUP.md) for where to find each Azure value.

---

### Step 3: Start Vault Enterprise

```bash
ansible-playbook ansible/playbooks/02-vault.yml
```

This will:
- Pull the `hashicorp/vault-enterprise:latest` container image
- Start Vault on port 8200
- Initialize Vault (generates 5 unseal key shares)
- Unseal Vault (uses 3 of 5 shares)
- Create the `admin` namespace

**After completion:**
- Vault UI: http://localhost:8200/ui
- Root token: `cat ~/.demo/vault/.vault-token`
- Init data: `~/.demo/vault/init.json`

> **Keep your init data safe!** The unseal keys and root token are the only
> way to recover your Vault instance. Back up `~/.demo/vault/init.json`.

---

### Step 4: Start MongoDB

```bash
ansible-playbook ansible/playbooks/03-mongodb.yml
```

This will:
- Pull `mongo:7.0`
- Start MongoDB on port 27017 with authentication enabled
- Create the `mongoadmin` user
- Create the `test` database and `products` collection with sample data

**After completion:**
- MongoDB: `localhost:27017`
- Admin password: `cat ~/.demo/mongodb/password`

---

### Step 5: Configure Vault (Terraform)

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` with your values. At minimum:
```hcl
vault_token               = ""   # cat ~/.demo/vault/.vault-token
mongo_password            = ""   # cat ~/.demo/mongodb/password
tenant_id                 = ""
mcp_client_id             = ""
agent_client_id           = ""
agent_client_secret       = ""
web_client_id             = ""
web_client_secret         = ""
readonly_group_object_id  = ""
readwrite_group_object_id = ""
```

Then run:
```bash
cd terraform
terraform init
terraform apply
```

Review the plan and type `yes` to confirm.

**After completion, note the outputs:**
```bash
terraform output vault_namespace   # e.g., admin/agentic-iam-abc123
terraform output app_url           # http://localhost:8501
```

Export the namespace:
```bash
export VAULT_NAMESPACE=$(terraform output -raw vault_namespace)
```

---

### Step 6: Start Application Containers

Source your environment and start the app stack:

```bash
# Load all env vars
set -a; source nerdctl-compose/.env; set +a

# Export Vault namespace from Terraform
export VAULT_NAMESPACE=$(cd terraform && terraform output -raw vault_namespace)

# Run the app-stack playbook
ansible-playbook ansible/playbooks/04-app-stack.yml
```

This generates the `.env` files for each container and starts them with nerdctl-compose.

---

### Step 7: Validate

```bash
./scripts/validate.sh
```

All services should show as healthy. If not, see Troubleshooting below.

---

### Step 8: Open the Demo

```
http://localhost:8501
```

Sign in as Alice (read-only) or Bob (read-write). See [TEST.md](./TEST.md) for the full demo walkthrough.

---

### Step 9: Open the Operator Dashboard (Optional)

```
http://localhost:8502
```

The **Vault Observer** is a read-only operator dashboard that reads the Vault audit log
and calls the Vault Identity API. Use it during the demo to show audiences what Vault
sees at each step of the authentication flow.

**Pages:**
| Page | What It Shows |
|------|--------------|
| Auth Events | Every JWT login: user, policies applied, entity ID, token TTL |
| Credential Issuance | Every dynamic DB credential: user, role, generated username, lease duration |
| Entity Explorer | Vault entities for Alice and Bob: aliases, group memberships, policies |
| Token Lifecycle | Token create/renew/revoke timeline |
| SIEM Context | What Vault logs provide vs what a SIEM adds (great for technical audiences) |

**Raw log access (CLI):**
```bash
# View all events pretty-printed
cat ~/.demo/vault/logs/audit.log | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if line:
        try: print(json.dumps(json.loads(line), indent=2)); print('---')
        except: print(line)
" | less

# Live tail during the demo
tail -f ~/.demo/vault/logs/audit.log | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if line:
        try: print(json.dumps(json.loads(line), indent=2)); print('---')
        except: print(line)
"

# Filter to auth events only
cat ~/.demo/vault/logs/audit.log | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if line:
        try:
            e = json.loads(line)
            if 'auth/jwt/login' in e.get('request', {}).get('path', ''):
                print(json.dumps(e, indent=2)); print('---')
        except: pass
"
```

---

## AWS Bedrock Setup (if using Option A)

The `products-agent` container needs AWS credentials to call Bedrock. Set these
before starting the containers:

```bash
export AWS_ACCESS_KEY_ID=<your-key-id>
export AWS_SECRET_ACCESS_KEY=<your-secret>
export AWS_DEFAULT_REGION=us-west-2
```

Or add them to `nerdctl-compose/.env`:
```
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_SESSION_TOKEN=
AWS_DEFAULT_REGION=us-west-2
BEDROCK_INFERENCE_PROFILE_ARN=arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0
```

To get the inference profile ARN:
1. AWS Console → Bedrock → **Inference profiles** (left nav)
2. Find the `global.anthropic.claude-*` profile
3. Copy the ARN

---

## Troubleshooting

### Vault won't start
```bash
nerdctl logs vault-enterprise
```
- `error loading configuration ... no such file or directory` — the volume mount for
  `~/.demo/vault/config` isn't working. Check `docker-compose.yml` uses the **absolute**
  path (e.g. `/Users/yourname/.demo/vault/config`), not `${HOME}` — nerdctl compose does
  not expand `${HOME}` in volume definitions.
- `storage configured to use "inmem"` — Vault is ignoring your config file and defaulting
  to dev mode. The compose service must include `command: vault server -config=/vault/config/vault.hcl`.
  Without it the image entrypoint uses inmem storage, which is unsupported for Enterprise.
- License error — verify `vault.hclic` is present in `~/.demo/vault/config/`.
- Port 8200 in use — `lsof -i :8200` and kill the conflicting process.

### Vault is sealed on restart
Vault must be unsealed after every container restart. Run from the project root:
```bash
export VAULT_ADDR=http://127.0.0.1:8200
python3 -c "
import json
d = json.load(open('/Users/joelevingston/.demo/vault/init.json'))
for k in d['keys_base64'][:3]:
    print(k)
" | while read key; do
  vault operator unseal "$key"
done
```
> The key array in `init.json` is `keys_base64` — not `unseal_keys_b64`.

### Vault token in terraform.tfvars is stale
After any Vault re-initialization the root token changes. Verify and update:
```bash
# Check current valid token
cat ~/.demo/vault/.vault-token

# Update tfvars
CURRENT_TOKEN=$(cat ~/.demo/vault/.vault-token)
sed -i '' "s|vault_token = \".*\"|vault_token = \"$CURRENT_TOKEN\"|" terraform/terraform.tfvars

# Re-apply
cd terraform && terraform apply
```

### MongoDB auth error
```bash
nerdctl logs mongodb
```
If the admin user already exists and you're getting auth errors:
```bash
cat ~/.demo/mongodb/password  # verify the password
nerdctl exec -it mongodb mongosh -u mongoadmin -p <password> --authenticationDatabase admin
```

### Containers can't reach Vault ("Connection timed out" in MCP logs)
Vault and the app containers must be on the **same compose network**. If Vault was started
as a standalone `nerdctl run` container it will be on a different subnet and unreachable
via `host.docker.internal` from inside other containers.

The `docker-compose.yml` now includes `vault-enterprise` and `mongodb` as services so all
containers share `confused-demo_demo-net`. If you previously ran them standalone, stop and
remove them, then start via compose:
```bash
nerdctl stop vault-enterprise mongodb
nerdctl rm vault-enterprise mongodb
cd nerdctl-compose && nerdctl compose up -d
# Then unseal Vault (see above)
```
Verify all containers are on the same network:
```bash
nerdctl inspect products-mcp --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
nerdctl inspect vault-enterprise --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
# Both should be on the same 10.4.x.x subnet
```

### Entra ID login fails
- Check that `REDIRECT_URI` in `.env` matches exactly what's in the Azure app registration
- Verify `WEB_CLIENT_ID` and `WEB_CLIENT_SECRET` are correct
- Try: `curl -s https://login.microsoftonline.com/<TENANT_ID>/v2.0/.well-known/openid-configuration | jq .issuer`

### Vault JWT auth — "permission denied" on /v1/auth/jwt/login
The `VAULT_NAMESPACE` in `nerdctl-compose/products-mcp/.env` must include the full path
with the `admin/` parent prefix:
```bash
grep VAULT_NAMESPACE nerdctl-compose/products-mcp/.env
# Expected: VAULT_NAMESPACE=admin/agentic-iam-<suffix>
# Wrong:    VAULT_NAMESPACE=agentic-iam-<suffix>   ← missing admin/ prefix
```
Get the correct value from Terraform output:
```bash
cd terraform && terraform output vault_namespace
# Returns: admin/agentic-iam-<suffix>
```
Update the file and restart MCP:
```bash
sed -i '' "s|VAULT_NAMESPACE=.*|VAULT_NAMESPACE=$(cd terraform && terraform output -raw vault_namespace)|" \
  nerdctl-compose/products-mcp/.env
cd nerdctl-compose && nerdctl compose restart products-mcp
```

### Vault JWT auth — "claim 'preferred_username' not found in token"
v1 access tokens (the default when `accessTokenAcceptedVersion` is `null` in the app
manifest) use `unique_name` for the UPN claim, not `preferred_username`. The Vault JWT
role in `terraform/vault-auth.tf` is already configured with `user_claim = "unique_name"`.
If you see this error after a `terraform apply`, verify:
```bash
grep user_claim terraform/vault-auth.tf
# Expected: user_claim = "unique_name"
```
Then re-apply and restart MCP:
```bash
cd terraform && terraform apply
cd nerdctl-compose && nerdctl compose restart products-mcp
```

### Vault JWT auth fails (general)
- Check Vault logs: `nerdctl logs vault-enterprise`
- Verify the JWT audience (`MCP_CLIENT_ID`) uses the `api://` prefix: `api://<client_id>`
- Enable verbose logging: set `verbose_oidc_logging = true` (already set in Terraform config)
- Confirm the JWT auth mount exists in the correct namespace:
```bash
VAULT_TOKEN=$(cat ~/.demo/vault/.vault-token)
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "X-Vault-Namespace: admin/agentic-iam-<suffix>" \
  http://127.0.0.1:8200/v1/sys/auth | python3 -m json.tool | grep jwt
# Should show the jwt/ mount
```

### "API Error: Invalid token: Invalid issuer"
Entra ID app registrations default to v1 access tokens (`iss = https://sts.windows.net/<tenant>/`).
The agent and MCP servers are configured to accept this. If you see this error after a fresh
`terraform apply` or config change, verify:
```bash
grep JWT_ISSUER nerdctl-compose/products-agent/.env nerdctl-compose/products-mcp/.env
# Expected: https://sts.windows.net/<tenant_id>/
```
If the value shows `login.microsoftonline.com/.../v2.0`, run:
```bash
sed -i '' 's|JWT_ISSUER=https://login.microsoftonline.com/.*|JWT_ISSUER=https://sts.windows.net/<TENANT_ID>/|' \
  nerdctl-compose/products-agent/.env nerdctl-compose/products-mcp/.env
cd nerdctl-compose && nerdctl compose down && nerdctl compose up -d
```

### "API Error: Invalid token: Audience doesn't match"
v1 access tokens carry the App ID URI (`api://<client_id>`) as their audience — not the bare GUID.
Verify your `.env` files use the `api://` prefix:
```bash
grep JWT_AUDIENCE nerdctl-compose/products-agent/.env nerdctl-compose/products-mcp/.env
# Expected:
#   products-agent: JWT_AUDIENCE=api://<AGENT_CLIENT_ID>
#   products-mcp:   JWT_AUDIENCE=api://<MCP_CLIENT_ID>
```
Also verify Vault's `bound_audiences` uses the `api://` prefix:
```bash
grep bound_audiences terraform/vault-auth.tf
# Expected: bound_audiences = ["api://${var.mcp_client_id}"]
```
If either is wrong, fix and run `terraform apply` + `nerdctl compose down && nerdctl compose up -d`.

### "API Error: Unable to locate credentials" (Bedrock)
**This is the most common issue for SEs doing this demo.** The `products-agent` uses
AWS Bedrock for LLM inference. HashiCorp SSO credentials expire every 8 hours.

The `docker-compose.yml` mounts `~/.aws` from your Mac directly into the agent container,
so the container always reads the same credentials as your host CLI. You only need to
refresh `~/.aws/credentials` — no container restart required.

**Every 8 hours** (after getting fresh credentials from HashiCorp SSO):
```bash
aws configure set aws_access_key_id     "ASIA..."
aws configure set aws_secret_access_key "..."
aws configure set aws_session_token     "..."
aws configure set region                us-west-2
```

Verify the container can now reach Bedrock:
```bash
nerdctl exec products-agent aws sts get-caller-identity
```

**If you see empty credentials inside the container** (e.g. after first deploy), the
`~/.aws` mount requires a one-time restart to activate:
```bash
cd nerdctl-compose && nerdctl compose down && nerdctl compose up -d
```
After that, credential refreshes via `aws configure set` take effect immediately — no
further restarts needed.

**Check current credential status at any time:**
```bash
source set-aws-creds.sh   # runs aws sts get-caller-identity and reports pass/fail
```

### products-web crashes (Segmentation fault / HTTP 000)
On Apple Silicon (M1/M2/M3/M4) Macs, running the `linux/amd64` images under QEMU causes
segfaults. All three app images have native `arm64` builds — use them instead:
```bash
# Verify you are on arm64
uname -m  # should print: arm64

# Check current platform setting
grep platform nerdctl-compose/.env
# If it shows linux/amd64, fix it:
sed -i '' 's/platform=linux\/amd64/platform=linux\/arm64/' nerdctl-compose/.env

# Pull native arm64 images and restart
nerdctl pull --platform linux/arm64 drum0r/products-web:latest
nerdctl pull --platform linux/arm64 drum0r/products-agent:latest
nerdctl pull --platform linux/arm64 drum0r/products-mcp:latest
cd nerdctl-compose && nerdctl compose down && nerdctl compose up -d
```

### Products not appearing on first query
This is expected behavior from the original demo. Run the query a second time.

---

## Re-deploying After Changes

If you change Terraform configuration:
```bash
cd terraform && terraform apply
```

If you change container configuration (`.env` files):
```bash
set -a; source nerdctl-compose/.env; set +a
export VAULT_NAMESPACE=$(cd terraform && terraform output -raw vault_namespace)
ansible-playbook ansible/playbooks/04-app-stack.yml
```

If you want to restart everything from scratch:
```bash
./scripts/teardown.sh --purge
./scripts/deploy.sh
```
