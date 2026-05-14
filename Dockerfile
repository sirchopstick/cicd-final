# ── Stage 1: builder ─────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .

RUN python -m venv /venv \
    && /venv/bin/pip install --no-cache-dir --upgrade pip \
    && /venv/bin/pip install --no-cache-dir -r requirements.txt

# ── Stage 2: final ───────────────────────────────────────────────────────────
FROM python:3.11-slim AS final

WORKDIR /app

# Copy only the pre-built venv and application code — no build tools in prod
COPY --from=builder /venv /venv
COPY app/ ./app/

# Non-root user for security
RUN useradd -m appuser
USER appuser

ENV PATH="/venv/bin:$PATH"

EXPOSE 8000

# Health check using the built-in Python (no extra packages needed)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
