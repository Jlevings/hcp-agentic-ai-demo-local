# Prerequisites

Everything you need to install before running the demo.

---

## Required Tools

### 1. Rancher Desktop (Container Runtime)

Rancher Desktop provides `nerdctl` (the container CLI) and the containerd runtime.

**Install:**
```bash
brew install --cask rancher
```

Or download from https://rancherdesktop.io

**First-time setup:**
1. Open Rancher Desktop from Applications
2. Go to **Preferences → Container Engine**
3. Select **containerd** (not dockerd)
4. Wait for initialization to complete (~2-3 minutes on first launch)
5. Ensure `nerdctl` is in your PATH:
   ```bash
   echo 'export PATH="$HOME/.rd/bin:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   nerdctl version  # verify
   ```

> **Docker Desktop users:** If you already have Docker Desktop installed, the compose files are compatible with `docker compose` as well. The `deploy.sh` script auto-detects which is available.

---

### 2. Terraform >= 1.5

Used to configure the local Vault Enterprise instance (auth methods, policies, secrets engine).

> **Note:** Homebrew's `terraform` formula is capped at 1.5.7 (last MPL-licensed version) and is deprecated in homebrew/core. Use **tfenv** to install current BUSL-licensed versions directly from HashiCorp releases.

**Install tfenv (Terraform version manager):**
```bash
brew install tfenv
```

If you see a symlink conflict with an existing `terraform` install, resolve it first:
```bash
brew unlink terraform   # removes the brew symlink, does not uninstall
brew link tfenv         # completes the tfenv setup
```

**Install and activate the desired Terraform version:**
```bash
tfenv install 1.14.7
tfenv use 1.14.7
terraform version  # verify
```

---

### 3. Ansible >= 2.14

Used to automate container startup, initialization, and configuration.

```bash
brew install ansible
ansible --version  # verify >= 2.14
```

Install required Ansible collections:
```bash
ansible-galaxy collection install community.general
```

---

### 4. Vault CLI

Used for smoke testing and manual Vault interaction.

```bash
brew install vault
vault version  # verify
```

---

### 5. AWS CLI (if using AWS Bedrock)

Required only if using AWS Bedrock as the LLM backend (the primary option).

```bash
brew install awscli
aws --version  # verify
```

**Configure AWS credentials:**

> **Dynamic credentials (recommended):** If your AWS credentials are short-lived (Vault AWS secrets engine, SSO, STS — typical lease: 8 hours), do **not** use `aws configure` as stale creds will be written to disk. Instead, use the provided helper:
>
> ```bash
> # 1. Paste fresh credentials into set-aws-creds.sh
> # 2. Source it into your current shell (must be sourced, not executed)
> source set-aws-creds.sh
> # 3. Verify
> aws sts get-caller-identity
> ```
>
> The compose stack automatically inherits `AWS_*` vars from the host shell — no additional config needed.

For static long-lived credentials (less common):
```bash
aws configure
# Enter: Access Key ID, Secret Access Key, region (us-west-2), output format (json)
```

**Enable Bedrock model access:**
1. Log into the AWS Console
2. Open [AWS Bedrock](https://us-west-2.console.aws.amazon.com/bedrock/home?region=us-west-2)
3. Navigate to **Model access** → **Enable specific models**
4. Enable **Anthropic Claude Sonnet** models
5. Get the inference profile ARN from **Inference profiles**

---

### 6. jq

JSON processor used by scripts.

```bash
brew install jq
jq --version  # verify
```

---

## Required Accounts

### Microsoft Azure (Free)

The demo uses Microsoft Entra ID (Azure AD) as the identity provider. You need:
- A free Azure account: https://azure.microsoft.com/free/
- Three app registrations (web, agent, mcp)
- Two security groups (db-readonly, db-readwrite)
- Two user accounts (Alice, Bob)

**See [ENTRA-ID-SETUP.md](./ENTRA-ID-SETUP.md) for complete step-by-step instructions.**

> Creating a free Azure account requires a Microsoft account and a phone number
> for verification. No credit card is required for Entra ID (free tier).

---

### AWS Account (if using Bedrock)

If using AWS Bedrock as the LLM backend:
- AWS account with Bedrock access in `us-west-2`
- Claude model access enabled (see AWS CLI section above)
- IAM user or role with `bedrock:InvokeModel` permission

**Minimum IAM policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-*"
    }
  ]
}
```

### Anthropic Account (if using Anthropic API directly)

Alternative to AWS Bedrock — simpler if you don't have AWS:
1. Create an account at https://console.anthropic.com
2. Go to **API Keys** → **Create key**
3. Set `ANTHROPIC_API_KEY` in your `.env` file

---

## Verify Everything Is Ready

Run the prerequisites check:
```bash
ansible-playbook ansible/playbooks/01-prerequisites.yml
```

This will check all tools and report any missing dependencies.

---

## System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 8 GB | 16 GB |
| Disk | 10 GB free | 20 GB free |
| CPU | 4 cores | 8 cores |
| OS | macOS 13+ | macOS 14+ |

> **Apple Silicon (M1/M2/M3):** Rancher Desktop handles x86 container emulation.
> The pre-built images target `linux/amd64` — Rosetta 2 provides translation.
> Performance is slightly slower than native ARM but fully functional.
