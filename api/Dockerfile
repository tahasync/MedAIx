# syntax=docker/dockerfile:1
#
# MedAIx API image.
#
# Why Docker instead of a native Render build command: the API shells out to the
# Tesseract binary (via pytesseract), and Tesseract is NOT part of Render's
# native Python runtime. apt-get packages installed during a native build
# command do not persist to the runtime container, so `tesseract` is missing at
# request time and every upload returns 503 "Tesseract is not installed".
# Baking Tesseract (plus the eng/urd traineddata) into the image is Render's
# documented way to ship a system dependency it does not preinstall.

FROM python:3.12-slim

# System dependencies, installed in a single cleaned layer to stay lean on
# Render's free tier:
#   tesseract-ocr        the OCR engine the API shells out to
#   tesseract-ocr-eng    English traineddata (english + roman_urdu modes)
#   tesseract-ocr-urd    Urdu traineddata (urdu mode uses urd+eng)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        tesseract-ocr \
        tesseract-ocr-eng \
        tesseract-ocr-urd \
    && rm -rf /var/lib/apt/lists/*

# uv — the project's package manager (see pyproject.toml / uv.lock).
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

WORKDIR /app

# uv settings:
#   UV_PYTHON_DOWNLOADS=never  use the image's own Python 3.12, never fetch one
#   UV_LINK_MODE=copy          make the virtualenv self-contained (real files,
#                              not hardlinks into a build cache absent from the
#                              image) so the runtime venv survives on its own
#   UV_PROJECT_ENVIRONMENT     fixed, known venv path referenced by the CMD
#   PYTHONPATH=/app            make `main` (and database/models/ocr) importable
#                              without installing the flat-layout project wheel
#   PORT                       Render injects the port; 8000 for local runs
ENV UV_PYTHON_DOWNLOADS=never \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    PYTHONPATH=/app \
    PORT=8000

# Install dependencies first (without the project) so this layer is cached and
# only invalidated when pyproject.toml / uv.lock change. Trim the uv cache so it
# is not baked into the final image.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project \
    && uv cache clean

# Application code.
COPY . .

EXPOSE 8000

# Run the venv's uvicorn directly — no uv, no re-sync, fastest cold start.
# $PORT is expanded by sh when the container starts.
CMD ["sh", "-c", "exec /app/.venv/bin/uvicorn main:app --host 0.0.0.0 --port $PORT"]
