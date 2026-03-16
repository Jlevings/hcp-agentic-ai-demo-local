# =============================================================================
# models.py — LLM backend selection (Anthropic API or AWS Bedrock)
# =============================================================================
# This file replaces the upstream models.py which was hardcoded to Bedrock.
#
# Selection logic (checked in order):
#   1. ANTHROPIC_API_KEY is set  →  Anthropic API (no AWS credentials needed)
#   2. Otherwise                 →  AWS Bedrock (original behaviour)
#
# The function name get_bedrock_model() is intentionally preserved so that
# products_agent.py (which calls it by name) requires zero changes.
# =============================================================================

import os
import logging

from strands.models import BedrockModel

logger = logging.getLogger(__name__)


def resolve_bedrock_config():
    """Read Bedrock settings from environment variables with safe defaults."""
    default_model_id = os.getenv("BEDROCK_MODEL_ID", "anthropic.claude-3-5-sonnet-20241022-v2:0")
    region          = os.getenv("BEDROCK_REGION", "us-east-1")
    temperature     = float(os.getenv("BEDROCK_TEMPERATURE", 0.1))
    profile_arn     = os.getenv("BEDROCK_INFERENCE_PROFILE_ARN")
    profile_id      = os.getenv("BEDROCK_INFERENCE_PROFILE_ID")
    resolved_model_id = profile_arn or profile_id or default_model_id
    return {
        "model_id":      resolved_model_id,
        "region":        region,
        "temperature":   temperature,
        "using_profile": bool(profile_arn or profile_id),
    }


def get_bedrock_model():
    """Return the configured LLM model for use by the Strands agent.

    If ANTHROPIC_API_KEY is present in the environment, returns an
    AnthropicModel so the demo runs entirely locally without AWS credentials.

    Otherwise falls back to BedrockModel (original behaviour), using
    BEDROCK_INFERENCE_PROFILE_ARN / BEDROCK_MODEL_ID / BEDROCK_REGION to
    select the model and region.
    """
    anthropic_key = os.getenv("ANTHROPIC_API_KEY")

    if anthropic_key:
        # ── Anthropic API path ────────────────────────────────────────────
        # Uses the Anthropic API directly — no AWS credentials required.
        # Model defaults to claude-sonnet-4-5; override with ANTHROPIC_MODEL_ID.
        from strands.models.anthropic import AnthropicModel

        model_id    = os.getenv("ANTHROPIC_MODEL_ID", "claude-sonnet-4-5")
        temperature = float(os.getenv("BEDROCK_TEMPERATURE", 0.1))

        logger.info("LLM backend: Anthropic API  model=%s", model_id)
        return AnthropicModel(
            model_id=model_id,
            max_tokens=8096,
            params={"temperature": temperature},
        )

    # ── Bedrock path (fallback) ───────────────────────────────────────────
    # Requires AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
    # to be available (via ~/.aws mount or environment variables).
    cfg = resolve_bedrock_config()
    if cfg["using_profile"]:
        logger.info("LLM backend: Bedrock inference profile  model=%s  region=%s",
                    cfg["model_id"], cfg["region"])
    else:
        logger.info("LLM backend: Bedrock model id  model=%s  region=%s",
                    cfg["model_id"], cfg["region"])

    return BedrockModel(
        model_id=cfg["model_id"],
        temperature=cfg["temperature"],
        region_name=cfg["region"],
        streaming=True,
    )
