# =============================================================================
# Dockerfile — vault-observer (Operator Audit Dashboard)
# =============================================================================
# Builds the Streamlit operator dashboard that reads Vault audit logs and
# calls the Vault API to display a human-readable identity trace.
#
# Base image: python:3.12-slim (small footprint, no unnecessary packages)
# Port: 8502
# =============================================================================

FROM python:3.12-slim

WORKDIR /app

# Install Python dependencies first (layer cached separately from app code)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the Streamlit application
COPY app.py .

# Run Streamlit in headless mode on port 8502.
# --server.headless=true      disables the browser auto-open prompt
# --browser.gatherUsageStats=false  disables telemetry
CMD ["streamlit", "run", "app.py", \
     "--server.port=8502", \
     "--server.address=0.0.0.0", \
     "--server.headless=true", \
     "--browser.gatherUsageStats=false"]
