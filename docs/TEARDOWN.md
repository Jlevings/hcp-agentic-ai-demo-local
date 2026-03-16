# Teardown Guide

Instructions for stopping and cleaning up the demo environment.

---

## Quick Teardown

```bash
./scripts/teardown.sh
```

This stops all containers and destroys the Vault configuration (Terraform state).
Vault and MongoDB data directories are **preserved** for quick re-deployment.

---

## Full Teardown (Purge Everything)

```bash
./scripts/teardown.sh --purge
```

This additionally:
- Deletes `~/.demo/vault/` (Vault data, init keys, root token)
- Deletes `~/.demo/mongodb/` (MongoDB data and admin password)
- Removes generated `.env` files
- Clears Terraform state

After a full purge, you must run the complete deployment again from Step 3.

---

## Stop Containers Only

If you want to stop containers without destroying Vault configuration:

```bash
./scripts/teardown.sh --containers-only

# Or manually:
nerdctl compose -f nerdctl-compose/docker-compose.yml down
nerdctl stop vault-enterprise mongodb
nerdctl rm vault-enterprise mongodb
```

---

## Manual Teardown Steps

If the script fails, perform these steps manually:

### 1. Stop Application Containers
```bash
nerdctl compose -f nerdctl-compose/docker-compose.yml --project-name confused-demo down
```

### 2. Destroy Vault Configuration
```bash
export VAULT_TOKEN=$(cat ~/.demo/vault/.vault-token)
export VAULT_ADDR=http://127.0.0.1:8200
export TF_VAR_vault_token="${VAULT_TOKEN}"
export TF_VAR_mongo_password=$(cat ~/.demo/mongodb/password)
cd terraform && terraform destroy
```

### 3. Stop and Remove Vault
```bash
nerdctl stop vault-enterprise && nerdctl rm vault-enterprise
```

### 4. Stop and Remove MongoDB
```bash
nerdctl stop mongodb && nerdctl rm mongodb
```

### 5. Clean Up Data (Optional)
```bash
rm -rf ~/.demo/vault ~/.demo/mongodb
```

---

## Re-deploying After Teardown (Without Purge)

Since Vault data is preserved, you can redeploy faster:

```bash
./scripts/deploy.sh --skip-infra --skip-terraform
```

Wait — if Vault data is preserved but containers are gone, you need to restart
infrastructure and re-unseal:

```bash
./scripts/deploy.sh
```

The playbooks detect existing initialization data and skip re-init.

---

## Troubleshooting Teardown

**Terraform destroy fails: "provider configuration not present"**
```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(cat ~/.demo/vault/.vault-token)
cd terraform && terraform destroy
```

**Container won't stop:**
```bash
nerdctl kill products-web products-agent products-mcp
nerdctl kill vault-enterprise mongodb
nerdctl rm products-web products-agent products-mcp vault-enterprise mongodb
```

**nerdctl-compose network not cleaning up:**
```bash
nerdctl network ls
nerdctl network rm confused-demo_demo-net
```
