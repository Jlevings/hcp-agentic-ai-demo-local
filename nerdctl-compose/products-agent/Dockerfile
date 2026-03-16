# =============================================================================
# products-agent/Dockerfile — Anthropic-enabled wrapper
# =============================================================================
# The upstream drum0r/products-agent image is hardcoded to AWS Bedrock via the
# AWS Strands SDK. This Dockerfile extends it to support Anthropic API as a
# drop-in alternative — no Bedrock or AWS credentials required when
# ANTHROPIC_API_KEY is set in the container's .env file.
#
# What this adds:
#   1. Installs the `anthropic` Python package (missing from upstream image).
#   2. Replaces /app/models.py with a version that checks ANTHROPIC_API_KEY
#      first and routes to AnthropicModel. Falls back to BedrockModel if the
#      key is absent, preserving full Bedrock compatibility.
#
# products_agent.py in the upstream image calls get_bedrock_model() by name —
# we keep that function name so no other files need changing.
# =============================================================================

FROM drum0r/products-agent:latest

# Install the anthropic SDK — required by strands.models.anthropic.AnthropicModel
# which exists in the strands package but has this optional dependency uninstalled.
RUN pip install --no-cache-dir anthropic

# Replace models.py with our patched version that adds Anthropic routing logic.
COPY models.py /app/models.py
