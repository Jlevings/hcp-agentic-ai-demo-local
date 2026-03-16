# Architecture — Vault Agentic IAM (Local)

## Overview

This demo implements the **Confused Deputy Problem** mitigation pattern using
HashiCorp Vault as the identity and authorization authority. It runs entirely
on your local machine, replacing the original AWS + HCP Vault infrastructure
with local containers.

---

## Identity Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LOCAL MACHINE (macOS)                             │
│                                                                      │
│  Browser                                                             │
│    │                                                                 │
│    │  1. Login (OIDC)                                                │
│    ▼                                                                 │
│  ┌──────────────────┐                                                │
│  │  products-web    │  Streamlit UI                                  │
│  │  :8501           │  Handles Entra ID OIDC login                  │
│  └────────┬─────────┘                                                │
│           │                                                          │
│           │  2. Chat request + access token (JWT)                   │
│           ▼                                                          │
│  ┌──────────────────┐                                                │
│  │  products-agent  │  Agent API (FastAPI)                          │
│  │  :8001           │  ┌──────────────────────────────┐             │
│  │                  │  │ 3. OBO Token Exchange         │             │
│  │                  │  │    POST /oauth2/v2.0/token    │             │
│  │                  │  │    grant_type=jwt-bearer      │             │
│  │                  │  └──────────────┬───────────────┘             │
│  └────────┬─────────┘                 │                             │
│           │              ┌────────────▼─────────────────┐           │
│           │              │   Microsoft Entra ID         │           │
│           │              │   (External / Cloud)         │           │
│           │              │   Returns OBO Token          │           │
│           │              └────────────┬─────────────────┘           │
│           │                           │                             │
│           │  4. MCP call + OBO token  │                             │
│           ▼                           │                             │
│  ┌──────────────────┐◄────────────────┘                             │
│  │  products-mcp    │  MCP Server (FastAPI)                         │
│  │  :8000           │                                               │
│  │                  │  5. JWT Login to Vault                        │
│  │                  │──────────────────────────────┐                │
│  └──────────────────┘                              │                │
│                                                    ▼                │
│                                          ┌──────────────────┐       │
│                                          │  Vault Enterprise│       │
│                                          │  :8200           │       │
│                                          │                  │       │
│                                          │  6. Validate JWT │       │
│                                          │  Extract groups  │       │
│                                          │  Map → Policy    │       │
│                                          │  Issue DB creds  │       │
│                                          └────────┬─────────┘       │
│                                                   │                 │
│  7. DB operation with                             │ short-lived     │
│     dynamic credentials                          │ credentials     │
│  ┌──────────────────┐◄──────────────────────────┘                  │
│  │  MongoDB         │                                               │
│  │  :27017          │  Products collection in 'test' database       │
│  └──────────────────┘                                               │
└─────────────────────────────────────────────────────────────────────┘

External Services (required, not replaceable):
  ┌────────────────────────┐    ┌────────────────────────┐
  │  Microsoft Entra ID    │    │  AWS Bedrock /          │
  │  (Azure AD)            │    │  Anthropic API          │
  │  - OIDC login          │    │  - Claude AI model      │
  │  - OBO token exchange  │    │  - NLP processing       │
  └────────────────────────┘    └────────────────────────┘
```

---

## Identity Flow Step-by-Step

| Step | Actor | Action | Result |
|------|-------|--------|--------|
| 1 | Browser → products-web | User clicks "Login" | Redirected to Entra ID OIDC |
| 2 | products-web → products-agent | Sends user message with access token (JWT) | Agent receives user context |
| 3 | products-agent → Entra ID | OBO token exchange (jwt-bearer grant) | Receives OBO token representing delegated user identity |
| 4 | products-agent → products-mcp | Calls MCP tool with OBO token | MCP validates token |
| 5 | products-mcp → Vault | JWT login (`vault write auth/jwt/login`) | Vault validates signature via JWKS |
| 6 | Vault (internal) | Extract `groups` claim → match alias → apply policy | Returns short-lived MongoDB credentials |
| 7 | products-mcp → MongoDB | Connect with dynamic credentials | Read or write depending on user's group |

---

## Why This Eliminates the Confused Deputy Problem

### The Problem (Without Vault)
```
User Request → Application → Database
                    │
                    └── Uses application's own credentials (admin)
                        Alice and Bob both get full access!
                        The "Deputy" (application) is confused about
                        whose identity to act under.
```

### The Solution (With Vault OBO Flow)
```
User Request → Application → Vault (validates user identity)
                                │
                                ├── Alice → readonly policy → read-only DB creds
                                └── Bob   → readwrite policy → read-write DB creds

The application NEVER holds elevated credentials.
It only uses credentials that Vault issued FOR the specific user.
```

---

## Component Inventory

| Component | Image | Port | Purpose |
|-----------|-------|------|---------|
| products-web | `drum0r/products-web:latest` | 8501 | Streamlit UI with Entra ID OIDC |
| products-agent | `drum0r/products-agent:latest` | 8001 | FastAPI agent, OBO exchange, Bedrock/Anthropic |
| products-mcp | `drum0r/products-mcp:latest` | 8000 | MCP server, Vault JWT auth, DB ops |
| Vault Enterprise | `hashicorp/vault-enterprise:latest` | 8200 | Secrets management, dynamic DB creds |
| MongoDB | `mongo:7.0` | 27017 | Products database |

---

## Vault Configuration

| Resource | Value | Purpose |
|----------|-------|---------|
| Namespace | `admin/agentic-iam-<suffix>` | Isolates demo config |
| Auth mount | `jwt` | Validates Entra ID OBO tokens |
| Secrets mount | `database` | Dynamic MongoDB credentials |
| Policy: `readonly` | `database/creds/readonly` | Alice's access |
| Policy: `readwrite` | `database/creds/readwrite` | Bob's access |
| Group: `readonly` | External, `readonly` policy | Maps Entra ID group → Vault policy |
| Group: `readwrite` | External, `readwrite` policy | Maps Entra ID group → Vault policy |
| DB role: `readonly` | MongoDB `read` on `test` db, 5min TTL | Short-lived read credentials |
| DB role: `readwrite` | MongoDB `readWrite` on `test` db, 5min TTL | Short-lived write credentials |

---

## Original vs. Local Architecture

| Layer | Original (DDR Platform) | Local (This Repo) |
|-------|------------------------|-------------------|
| Identity Provider | Entra ID (pre-configured) | Entra ID (free Azure account) |
| Vault | HCP Vault Enterprise (cloud) | Vault Enterprise container (local) |
| Database | AWS DocumentDB (MongoDB compatible) | MongoDB container (local) |
| Compute | AWS EC2 (bastion host) | localhost |
| Networking | AWS VPC + ALB + ACM | localhost (HTTP, no TLS) |
| Infrastructure as Code | Terraform Cloud (no-code module) | Terraform OSS + Ansible |
| LLM | AWS Bedrock (Claude) | AWS Bedrock or Anthropic API |
| Container Runtime | Docker on EC2 | nerdctl (Rancher Desktop) or Docker Desktop |
