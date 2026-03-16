# Microsoft Entra ID Setup Guide

This guide walks you through creating a free Azure account and configuring
all required Entra ID resources for the Vault Agentic IAM demo.

**Time required:** ~30 minutes

---

## Overview

You will create:
- 1 Azure free account (if you don't have one)
- 3 App Registrations: `products-web`, `products-agent`, `products-mcp`
- 2 Security Groups: `db-readonly`, `db-readwrite`
- 2 User accounts: Alice (read-only), Bob (read-write)

---

## Step 1: Create a Free Azure Account

> Skip this step if you already have an Azure account.

1. Go to https://azure.microsoft.com/free/
2. Click **Start free**
3. Sign in with your Microsoft account (or create one)
4. Complete phone verification
5. No credit card is required for Entra ID (free tier)

---

## Step 2: Find Your Tenant ID

You'll need this for all configuration files.

1. Go to [Azure Portal](https://portal.azure.com)
2. Search for **Entra ID** (or **Azure Active Directory**)
3. On the Overview page, copy the **Tenant ID**
4. Save it — you'll use it everywhere as `TENANT_ID`

---

## Step 3: Register the `products-mcp` App

This app represents the MCP server. Vault validates tokens against this app's audience.

> **Note:** `products-mcp` only **exposes** an API — it does NOT add permissions to call other apps.
> Do not add anything under "API permissions → My APIs" for this app.

1. In Azure Portal → **Entra ID** → **App registrations** → **New registration**
2. Fill in:
   - **Name:** `products-mcp`
   - **Supported account types:** Select **Single tenant only - Default Directory**
   - **Redirect URI:** Leave blank (select platform is not required)
3. Click **Register**
4. On the Overview page, copy:
   - **Application (client) ID** → save as `MCP_CLIENT_ID`
5. Go to **Manifest** (left sidebar of the app registration in Azure Portal):
   - You will see a JSON editor directly in the browser — this is the app's configuration in Azure, not a local file.
   - Find the line: `"groupMembershipClaims": null,`
   - Change it to: `"groupMembershipClaims": "SecurityGroup",`
   - Full example:
     ```json
     "groupMembershipClaims": "SecurityGroup",
     ```
   - This makes Entra ID include group Object IDs in the JWT `groups` claim, which Vault reads to determine which policy to apply.
6. Click **Save** at the top of the Manifest editor
7. Go to **Expose an API** (left sidebar) → next to **Application ID URI** click **Add** → accept the default → click **Save**
8. Click **Add a scope**:
   - **Scope name:** `access`
   - **Who can consent:** Admins and users
   - **Admin consent display name:** Access Products MCP
   - **Admin consent description:** Allows access to the Products MCP server
   - Click **Add scope**
9. Copy the full scope URI (e.g., `api://YOUR_MCP_CLIENT_ID/access`) → save as `MCP_SCOPE`

> **`products-mcp` is now complete.** The `access` scope you just created is what makes this app
> appear under "My APIs" when you configure `products-agent` in the next step.

---

## Step 4: Register the `products-agent` App

This app represents the Agent API. It performs the OBO token exchange.

1. **App registrations** → **New registration**
2. Fill in:
   - **Name:** `products-agent`
   - **Supported account types:** Select **Single tenant only - Default Directory**
   - **Redirect URI:** Leave blank (select platform is not required)
3. Click **Register**
4. Copy the **Application (client) ID** → save as `AGENT_CLIENT_ID`
5. Go to **Certificates & secrets** → **New client secret**:
   - **Description:** `demo-secret`
   - **Expires:** 24 months
   - Click **Add** — the table will show two columns: **Value** and **Secret ID**
   - Copy the **Value** column only → save as `AGENT_CLIENT_SECRET`
   - The **Secret ID** column is Azure's internal identifier — you do not need it
   > You cannot retrieve the Value after leaving this page — copy it now!
6. Go to **Manifest** (left sidebar in Azure Portal) → find `"groupMembershipClaims": null,` → change to `"groupMembershipClaims": "SecurityGroup",` → **Save**
7. Go to **API permissions** → **Add a permission**
   - Click the **APIs my organization uses** tab (more reliable than "My APIs" in a fresh tenant)
   - Search for `products-mcp` → select it
   - Check the `access` scope
   - Click **Add permissions**
   > **Still no results?** Ensure you completed steps 7-9 of Step 3 (Expose an API on `products-mcp`), then wait 2-3 minutes and try again.
8. Click **Grant admin consent for Default Directory** → Yes
9. Go to **Expose an API** (left sidebar) → click **Add** next to "Application ID URI" → accept the pre-filled default → click **Save**
10. Click **Add a scope**:
    - **Scope name:** `access`
    - **Who can consent:** Admins and users
    - **Admin consent display name:** `Access Products Agent`
    - **Admin consent description:** `Allows access to the Products Agent`
    - Click **Add scope**
11. Copy the full scope URI (e.g., `api://YOUR_AGENT_CLIENT_ID/access`) → save as `AGENT_SCOPE`

---

## Step 5: Register the `products-web` App

This app represents the Streamlit frontend. Users log in through this app.

1. **App registrations** → **New registration**
2. Fill in:
   - **Name:** `products-web`
   - **Supported account types:** Select **Single tenant only - Default Directory**
   - **Redirect URI:**
     - From the **Select a platform** dropdown, choose **Web**
     - URI: `http://localhost:8501/callback`
3. Click **Register**
4. Copy the **Application (client) ID** → save as `WEB_CLIENT_ID`
5. Go to **Certificates & secrets** → **New client secret**:
   - **Description:** `demo-secret`
   - **Expires:** 24 months
   - Click **Add** → copy the **Value** column only → save as `WEB_CLIENT_SECRET`
   - The **Secret ID** is not needed
6. Go to **API permissions** → **Add a permission**
   - Click the **APIs my organization uses** tab
   - Search for `products-agent` → select it
   - Check the `access` scope
   - Click **Add permissions**
7. Also add: **Microsoft Graph** → **Delegated** → `openid`, `profile`, `email`
8. Click **Grant admin consent for [your tenant]** → Yes

**Build your scope strings locally** — these are not set in Azure. Substitute your saved client IDs and paste the result into `nerdctl-compose/.env` and `terraform/terraform.tfvars`:

```
# WEB_SCOPES — replace with your actual AGENT_CLIENT_ID
WEB_SCOPES=openid profile email api://YOUR_AGENT_CLIENT_ID/access

# AGENT_SCOPES — replace with your actual MCP_CLIENT_ID
AGENT_SCOPES=api://YOUR_MCP_CLIENT_ID/access
```

Example with real values:
```
WEB_SCOPES=openid profile email api://e57884f6-6410-4ecf-ac9d-686758f37b57/access
AGENT_SCOPES=api://a6035fa5-0203-43ce-8a10-07246320031a/access
```

---

## Step 6: Create Security Groups

These groups control which Vault policy users receive.

### Create `db-readonly` Group (Alice's group)

1. **Entra ID** → **Groups** → **New group**
2. Fill in:
   - **Group type:** Security
   - **Group name:** `db-readonly`
   - **Description:** Read-only database access
   - **Membership type:** Assigned
3. Click **Create**
4. Open the group → **Overview** → copy the **Object ID** → save as `READONLY_GROUP_OBJECT_ID`

### Create `db-readwrite` Group (Bob's group)

1. **Groups** → **New group**
2. Fill in:
   - **Group type:** Security
   - **Group name:** `db-readwrite`
   - **Description:** Read-write database access
   - **Membership type:** Assigned
3. Click **Create**
4. Copy the **Object ID** → save as `READWRITE_GROUP_OBJECT_ID`

---

## Step 7: Create Demo Users

### Create Alice (Read-Only User)

1. **Entra ID** → **Users** → **New user** → **Create new user**
2. Fill in:
   - **User principal name:** The field is split — type `alice` in the left text box only. The `@yourtenant.onmicrosoft.com` domain is selected automatically in the dropdown to the right. Do not include the `@` symbol in the text box.
   - **Display name:** `Alice Mateo`
   - **Password:** Select **Auto-generate password** or enter one manually — save it as `ALICE_PASSWORD`
3. Click **Create**
4. Save the full UPN (`alice@yourtenant.onmicrosoft.com`) as `ALICE_USERNAME`

**Add Alice to db-readonly group:**
1. Open `db-readonly` group → **Members** → **Add members**
2. Search for Alice → select → **Select**

### Create Bob (Read-Write User)

1. **Users** → **New user** → **Create new user**
2. Fill in:
   - **User principal name:** Type `bob` in the left text box only — the domain dropdown fills automatically
   - **Display name:** `Bob Carter`
   - **Password:** Auto-generate or set manually — save as `BOB_PASSWORD`
3. Click **Create**
4. Save the full UPN (`bob@yourtenant.onmicrosoft.com`) as `BOB_USERNAME`

**Add Bob to db-readwrite group:**
1. Open `db-readwrite` group → **Members** → **Add members**
2. Search for Bob → select → **Select**

---

## Step 8: Configure MFA (Required for Demo Users)

The demo users must set up MFA before the demo. Do this now to avoid doing it live.

> **Important:** Azure requires a password change on first login. The new password
> you set is what goes into your `.env` and `terraform.tfvars` files — not the
> original password you used when creating the account.

1. Open a new **incognito/private browser window**
2. Go to https://login.microsoftonline.com
3. Sign in as Alice (`alice@yourtenant.onmicrosoft.com` with the initial `ALICE_PASSWORD`)
4. Azure will immediately prompt you to **update your password** — set a new one and save it
5. You will then be prompted to set up MFA:
   - Use **Microsoft Authenticator** or any TOTP app (1Password, Authy, Google Authenticator)
   - Follow the prompts to scan the QR code
6. Complete the MFA setup and sign out
7. **Update `ALICE_PASSWORD`** in both `nerdctl-compose/.env` and `terraform/terraform.tfvars` with the new password you just set
8. Repeat steps 1-7 for Bob, updating `BOB_PASSWORD` in both files with his new password

---

## Step 9: Collect All Values

Fill these into `nerdctl-compose/.env` and `terraform/terraform.tfvars`:

```bash
TENANT_ID=                    # Step 2
WEB_CLIENT_ID=                # Step 5
WEB_CLIENT_SECRET=            # Step 5
AGENT_CLIENT_ID=              # Step 4
AGENT_CLIENT_SECRET=          # Step 4
MCP_CLIENT_ID=                # Step 3
READONLY_GROUP_OBJECT_ID=     # Step 6
READWRITE_GROUP_OBJECT_ID=    # Step 6
ALICE_USERNAME=               # Step 7 (alice@yourtenant.onmicrosoft.com)
ALICE_PASSWORD=               # Step 7
BOB_USERNAME=                 # Step 7 (bob@yourtenant.onmicrosoft.com)
BOB_PASSWORD=                 # Step 7

# Scopes
WEB_SCOPES=openid profile email api://AGENT_CLIENT_ID/access
AGENT_SCOPES=api://MCP_CLIENT_ID/access

REDIRECT_URI=http://localhost:8501/callback
```

---

## Troubleshooting

**"AADSTS50011: The redirect URI specified in the request does not match"**
→ Verify `REDIRECT_URI` exactly matches what you entered in the `products-web` app registration.

**"AADSTS65001: The user or administrator has not consented to use the application"**
→ Go to **API permissions** for the affected app and click **Grant admin consent**.

**"groups claim missing from JWT"**
→ Ensure `"groupMembershipClaims": "SecurityGroup"` is set in the app Manifest.

**JWT groups claim shows GUID but doesn't match**
→ Verify the group Object IDs you saved in Step 6 match what's in the JWT.
   Decode the JWT at https://jwt.ms to inspect claims.
