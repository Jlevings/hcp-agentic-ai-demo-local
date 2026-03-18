# Vault Agentic IAM — Local Edition

> **HashiCorp Vault eliminates the Confused Deputy Problem in agentic AI.**
> This demo runs the full identity-aware AI stack on your MacBook — no cloud infrastructure required.

---

## The Problem: Confused Deputy in Agentic AI

AI agents are increasingly making real decisions on behalf of real users — reading records, writing data, calling APIs. But most agentic architectures have a critical flaw: **the agent acts with its own elevated service credentials, not the user's actual permissions.**

This is the **Confused Deputy Problem**:

```
User Alice (read-only)  →  AI Agent (admin credentials)  →  Database
                                     ↑
                            Acts with its own power,
                            not Alice's. Can write, delete,
                            escalate — even if Alice cannot.
```

The result? One compromised agent token = full database access for any user, any prompt, any time.

---

## The Solution: Vault as the Identity Authority

HashiCorp Vault eliminates the Confused Deputy Problem by making the agent **incapable** of acting beyond the user's permissions:

```
User Alice (read-only)
    │ signs in via Entra ID JWT
    ▼
products-web (Streamlit UI)
    │ forwards JWT with every request
    ▼
products-agent (AI Agent / Claude)
    │ performs Entra ID On-Behalf-Of (OBO) token exchange
    │ → OBO token = cryptographically delegated user identity
    ▼
products-mcp (MCP Server — security enforcement point)
    │ presents OBO token to Vault JWT auth
    │ Vault validates token, reads `groups` claim
    │ maps Entra ID group Object ID → Vault policy
    │ issues short-lived MongoDB credential (5-minute TTL)
    ▼
MongoDB (with per-user ephemeral credential)
    │ Alice's credential → read-only role
    │ Bob's credential   → read-write role
    ▼
Result: Alice cannot write. Bob can. Zero application logic required.
```

**Every credential is:**
- Tied to the authenticated user's identity — not the service
- Short-lived (5-minute TTL) — automatically expires
- Dynamically generated — never stored, never reused
- Fully auditable — every issuance logged in Vault

---

## What This Demo Shows

| Scenario | What Vault Does |
|----------|----------------|
| Alice asks "list all products" | Issues read-only MongoDB credential for Alice |
| Alice asks "add a product" | Credential has no write permission → operation rejected |
| Bob asks "add a product" | Issues read-write MongoDB credential for Bob → operation succeeds |
| Agent is compromised | Credentials expired in 5 min, no lateral movement possible |

**The application contains zero authorization logic.** All permission enforcement happens in Vault, driven by the user's Entra ID group membership.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     localhost                            │
│                                                         │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────┐  │
│  │ products-web│───▶│products-agent│───▶│products-  │  │
│  │ :8501       │    │ :8001        │    │mcp :8000  │  │
│  │ Streamlit   │    │ Claude AI    │    │           │  │
│  │ Entra ID    │    │ OBO exchange │    │Vault JWT  │  │
│  │ OIDC login  │    │              │    │auth +     │  │
│  └─────────────┘    └──────────────┘    │dynamic DB │  │
│                                         │creds      │  │
│                                         └─────┬─────┘  │
│                                               │         │
│  ┌────────────────────┐    ┌──────────────────▼──────┐  │
│  │  Vault Enterprise  │◀───│      MongoDB :27017     │  │
│  │  :8200             │    │  Per-user ephemeral      │  │
│  │  JWT auth          │    │  credentials (5min TTL)  │  │
│  │  Dynamic DB creds  │    └─────────────────────────┘  │
│  │  Identity groups   │                                 │
│  └────────────────────┘                                 │
└─────────────────────────────────────────────────────────┘

External:  Microsoft Entra ID (identity provider + OBO flow)
           Anthropic API or AWS Bedrock (LLM inference)
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the detailed identity flow.

---

## Quick Deploy

### Prerequisites

| Tool | Install |
|------|---------|
| Rancher Desktop (nerdctl) | `brew install --cask rancher` |
| Terraform ≥ 1.5 | `brew install terraform` |
| Ansible ≥ 2.14 | `brew install ansible` |
| jq | `brew install jq` |
| Vault CLI | `brew tap hashicorp/tap && brew install hashicorp/tap/vault` |
| Azure free account | [portal.azure.com](https://portal.azure.com) — for Entra ID |
| Anthropic API key or AWS Bedrock access | [console.anthropic.com](https://console.anthropic.com) |

Full install guide: [docs/PREREQUISITES.md](docs/PREREQUISITES.md)

---

### Step 1: Azure Setup (~30 minutes, one-time)

Create 3 app registrations, 2 security groups, and 2 test users in Entra ID.

**Follow:** [docs/ENTRA-ID-SETUP.md](docs/ENTRA-ID-SETUP.md)

---

### Step 2: Configure Environment

```bash
cp nerdctl-compose/.env.example nerdctl-compose/.env
```

Edit `.env` with your Azure values:

```bash
TENANT_ID=<your-azure-tenant-id>
WEB_CLIENT_ID=<products-web client ID>
WEB_CLIENT_SECRET=<products-web client secret>
AGENT_CLIENT_ID=<products-agent client ID>
AGENT_CLIENT_SECRET=<products-agent client secret>
MCP_CLIENT_ID=<products-mcp client ID>
READONLY_GROUP_OBJECT_ID=<db-readonly group Object ID>
READWRITE_GROUP_OBJECT_ID=<db-readwrite group Object ID>
WEB_SCOPES=openid profile email api://<AGENT_CLIENT_ID>/access
AGENT_SCOPES=api://<MCP_CLIENT_ID>/access
REDIRECT_URI=http://localhost:8501/callback

# LLM — choose one:
ANTHROPIC_API_KEY=<your-key>          # Option A: Anthropic API (recommended)
# BEDROCK_INFERENCE_PROFILE_ARN=<arn> # Option B: AWS Bedrock
```

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Fill in with the same Azure values (Vault/MongoDB values populated after deploy)
```

---

### Step 3: Deploy

```bash
./scripts/deploy.sh
```

This automates the full stack:
1. Starts Vault Enterprise (local container, port 8200)
2. Initializes and unseals Vault
3. Starts MongoDB (local container, port 27017) with seed product data
4. Runs Terraform to configure Vault: JWT auth, policies, identity groups, dynamic DB secrets
5. Starts the three app containers (products-mcp, products-agent, products-web)
6. Validates all services are healthy

**Deploy time: ~5–8 minutes**

---

### Step 4: Open the Demo

| Service | URL |
|---------|-----|
| **Demo App** | http://localhost:8501 |
| **Operator Dashboard** | http://localhost:8502 |
| Vault UI | http://localhost:8200/ui |
| Agent API | http://localhost:8001 |
| MCP Server | http://localhost:8000 |

---

## Running the Demo

### Talk Track

**Opening:**
> "Today I'll show you how HashiCorp Vault eliminates the Confused Deputy Problem — one of the most common and dangerous vulnerabilities in agentic AI architectures. You'll see how user identity flows from Microsoft Entra ID through an AI agent all the way to the database, and how Vault enforces least privilege at every step — automatically."

**Architecture walkthrough:**
> "When a user logs in, Entra ID issues a signed JWT. The application forwards that token to our AI agent. The agent performs an On-Behalf-Of exchange — this creates a new token that cryptographically proves the agent is acting *as* the user, not as itself. That delegated token is presented to Vault, which validates it, reads the user's group memberships, and issues short-lived MongoDB credentials scoped to exactly what the user is allowed to do. Every credential expires in 5 minutes. Nothing is stored."

---

### Demo Sequence

#### 1. Sign in as Alice (read-only)

Open [http://localhost:8501](http://localhost:8501) in an **incognito window**.
Sign in with Alice's credentials.

**Prompt 1 — Read:**
```
List all products
```
> Products appear. ✅ Vault issued a read-only MongoDB credential.

**Prompt 2 — Write (should fail):**
```
Add a new product named "Chair Model X" with price $49.99
```
> Operation rejected. ✅ Alice's read-only credential has no write permission.

**Talk Track:**
> "Alice's Entra ID group membership — `db-readonly` — was encoded in her JWT. Vault read that claim, mapped it to the `readonly` policy, and issued a credential that literally cannot write to MongoDB. The application enforced nothing. Vault enforced everything."

---

#### 2. Sign in as Bob (read-write)

Open a **new incognito window** at [http://localhost:8501](http://localhost:8501).
Sign in with Bob's credentials.

**Prompt 1 — Read:**
```
List all products
```
> Products appear. ✅

**Prompt 2 — Write (should succeed):**
```
Add a new product named "Table Model Y" with price $89.99
```
> Product added successfully. ✅ Vault issued a read-write MongoDB credential.

**Talk Track:**
> "Bob's group is `db-readwrite`. Same token flow, same application code — but Vault issued different credentials. That's the power of identity-driven authorization. No role checks in the app. No static API keys. Just Vault, continuously enforcing policy at the moment of access."

---

#### 3. Show the Operator Dashboard (high-impact for technical audiences)

Open [http://localhost:8502](http://localhost:8502) — the Vault Observer dashboard.

- **Auth Events** — shows Alice's JWT login, the `readonly` policy Vault applied, and her entity ID
- **Credential Issuance** — shows each dynamically generated MongoDB username and its 5-minute TTL
- **Entity Explorer** — shows Alice and Bob as distinct Vault entities with their group memberships
- **Token Lifecycle** — shows token creation and expiry for each session
- **SIEM Context** — explains what Vault logs provide vs what a SIEM adds

**Talk Track:**
> "This is what an operator sees in real time. Every login, every credential issuance, every policy decision — all structured, identity-correlated, and readable without any additional tooling. In production you'd pipe this JSON into Splunk or Datadog, but even without a SIEM, the full audit trail is right here."

**Raw log access (CLI):**
```bash
# Live tail during the demo
tail -f ~/.demo/vault/logs/audit.log | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if line:
        try: print(json.dumps(json.loads(line), indent=2)); print('---')
        except: print(line)
"
```

---

#### 4. Show Vault UI (optional but powerful)

Open [http://localhost:8200/ui](http://localhost:8200/ui) → navigate to the `admin/agentic-iam-*` namespace:

- **Secrets → database/creds** — show the readonly and readwrite roles
- **Access → JWT** — show the JWT auth backend bound to Entra ID
- **Access → Entities** — show Alice and Bob as Vault entities after first login
- **Access → Groups** — show the external groups linked to Entra ID Object IDs

**Talk Track:**
> "Every time Alice or Bob authenticates, Vault creates a record. The audit trail shows exactly who accessed what, when, and with which credential. No guessing, no after-the-fact forensics."

---

### Cleanup

After the demo, sign out and close the incognito windows. Credentials expire automatically (5-minute TTL).

To stop the environment:
```bash
./scripts/teardown.sh
```

To fully reset (wipe all Vault state and MongoDB data):
```bash
./scripts/teardown.sh --purge
```

---

## Key Concepts

### On-Behalf-Of (OBO) Token Flow

OBO is a Microsoft Entra ID feature that lets a middle-tier service (the AI agent) exchange a user's access token for a new token that represents the user's identity when calling downstream services. This is different from client credentials — the downstream service *knows* it is acting as the user.

### Dynamic Secrets

Vault's database secrets engine generates unique, short-lived credentials on demand. No credential is shared between users or reused across sessions. If a credential is leaked, it expires within minutes.

### Vault Identity Groups

Vault external groups are linked to Entra ID security groups via group Object IDs in the JWT `groups` claim. When a user logs in, Vault reads their group memberships and applies the corresponding policy — no manual provisioning required.

---

## Documentation

| Document | Purpose |
|----------|---------|
| [docs/PREREQUISITES.md](docs/PREREQUISITES.md) | Install all required tools |
| [docs/ENTRA-ID-SETUP.md](docs/ENTRA-ID-SETUP.md) | Azure app registration walkthrough |
| [docs/DEPLOY.md](docs/DEPLOY.md) | Detailed deployment guide + troubleshooting |
| [docs/TEST.md](docs/TEST.md) | Step-by-step demo validation |
| [docs/TEARDOWN.md](docs/TEARDOWN.md) | Teardown and cleanup |
| [docs/FIELD-RESOURCES.md](docs/FIELD-RESOURCES.md) | Original talk track, slide deck links, demo recording |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture diagram + identity flow |

---

## Project Structure

```
.
├── README.md                       ← You are here
├── terraform/                      ← Vault configuration (auth, policies, DB secrets)
│   ├── main.tf                     ← Vault namespace
│   ├── vault-auth.tf               ← JWT auth, policies, identity groups + aliases
│   ├── vault-database.tf           ← Database secrets engine + readonly/readwrite roles
│   └── terraform.tfvars.example    ← Fill this in and copy to terraform.tfvars
├── ansible/                        ← Infrastructure automation
│   └── playbooks/
│       ├── 01-prerequisites.yml    ← Tool verification
│       ├── 02-vault.yml            ← Vault container + init + unseal
│       ├── 03-mongodb.yml          ← MongoDB + seed data
│       └── 04-app-stack.yml        ← App containers + .env injection
├── nerdctl-compose/                ← Container stack
│   ├── docker-compose.yml          ← Full 5-service stack
│   ├── .env.example                ← Environment variable template
│   └── products-agent/
│       ├── Dockerfile              ← Extends upstream image with Anthropic support
│       └── models.py               ← Anthropic/Bedrock routing logic
├── scripts/
│   ├── deploy.sh                   ← One-command deploy
│   ├── teardown.sh                 ← Full teardown
│   └── validate.sh                 ← Health checks
└── docs/                           ← Full documentation
```

---

## What Changed from the Original

This is a local adaptation of the [HashiCorp demo-vault-agentic-iam](https://github.com/Jlevings/demo-vault-agentic-iam), which originally ran on AWS + HCP Vault.

| Original | This Local Version |
|----------|-------------------|
| HCP Vault Enterprise (cloud) | Vault Enterprise container (localhost:8200) |
| AWS DocumentDB | MongoDB container (localhost:27017) |
| AWS EC2 + VPC + ALB | localhost — no cloud infrastructure |
| Terraform Cloud (no-code module) | Terraform OSS + Ansible automation |
| HCP Packer AMIs | Pre-built Docker images |
| HTTPS / ACM certs | HTTP — local dev, no certs needed |

**Unchanged:** Microsoft Entra ID (identity provider), Vault JWT auth + OBO flow, dynamic DB credentials pattern, pre-built application images.

---

## Field Resources

- **Demo Recording:** [Golden walkthrough](https://drive.google.com/file/d/1WpbQ3ArA3JP3gz5Rs96jXY29HOUQJVNC/view?usp=sharing) — recommended workflow for delivering this demo
- **OBO Flow Recording:** [Identity flow walkthrough](https://drive.google.com/file/d/1QfWIGRnEM_b0RimVtSE4cBLWsUKFsJJ3/view?usp=sharing)
- **Slide Deck:** [Agentic IAM with Vault](https://docs.google.com/presentation/d/1Oq-xhAyBq9mFfVaPgPhR9iabJNPLobAthSZnoWwF8IE/edit)
- **Full Talk Track:** [docs/FIELD-RESOURCES.md](docs/FIELD-RESOURCES.md)

---

## Troubleshooting

The most common issues and fixes are documented in [docs/DEPLOY.md — Troubleshooting](docs/DEPLOY.md#troubleshooting).

Quick reference:

| Issue | Fix |
|-------|-----|
| `products-web` HTTP 000 / segfault | Apple Silicon: set `platform=linux/arm64` in `.env`, pull native arm64 images |
| "Invalid token: Invalid issuer" | v1 tokens: `JWT_ISSUER=https://sts.windows.net/<tenant>/` |
| "Invalid token: Audience doesn't match" | v1 tokens: `JWT_AUDIENCE=api://<client_id>` (not bare GUID) |
| "Unable to locate credentials" | Set `ANTHROPIC_API_KEY` in `.env` for local LLM — no AWS needed |
| "Permission denied" on Vault JWT login | `VAULT_NAMESPACE` must include `admin/` prefix |
| "Access token expired" in UI | Log out and log back in — Entra ID tokens expire after ~1 hour |
| Vault connection timeout from containers | All containers must be on the same compose network |
| Vault defaults to inmem storage on restart | Compose service must have `command: vault server -config=...` |
| Vault sealed after restart | Run the unseal script (see [docs/DEPLOY.md](docs/DEPLOY.md#vault-is-sealed-on-restart)) |
| Empty products on first query | Expected — run the query a second time |
