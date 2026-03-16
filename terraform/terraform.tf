# =============================================================================
# terraform.tf — Provider Requirements and Optional Backend
# =============================================================================
# Declares the required Terraform and provider versions.
# The Vault provider configures all Vault resources (auth, policies, secrets).
# The random provider generates unique suffixes for the demo namespace.
#
# OPTIONAL: Uncomment the cloud {} block to use Terraform Cloud as the backend.
# When using TFC, remove or comment out terraform.tfvars and instead set
# variables via the TFC workspace UI or variable sets.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    # Vault provider — manages Vault auth methods, policies, secrets engines,
    # identity groups, and namespace configuration
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }

    # Random provider — generates a unique suffix appended to the Vault
    # namespace name so multiple demo environments can coexist
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # ── Optional: Terraform Cloud Backend ──────────────────────────────────────
  # Uncomment this block to store state in Terraform Cloud instead of locally.
  # Set TF_TOKEN_app_terraform_io or run `terraform login` before applying.
  #
  # cloud {
  #   organization = "your-org-name"
  #   workspaces {
  #     name = "vault-agentic-iam-local"
  #   }
  # }
}
