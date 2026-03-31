# ============================================================
# Stage 1: Build Vue frontend (node_modules stay in this stage)
# ============================================================
FROM node:22-slim AS frontend-build

WORKDIR /app
COPY package.json package-lock.json ./
COPY frontend/package.json frontend/package-lock.json ./frontend/
RUN npm ci && npm ci --prefix frontend
COPY frontend/ ./frontend/
COPY static/ ./static/
RUN cd frontend && npm run build

# ============================================================
# Stage 2: Install Python dependencies into .venv
# ============================================================
FROM python:3.11-slim AS python-build

WORKDIR /app/backend
COPY --from=ghcr.io/astral-sh/uv:0.9.26 /uv /uvx /bin/
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --frozen --no-install-project --no-dev

# ============================================================
# Stage 3: Minimal runtime image
# ============================================================
FROM python:3.11-slim

# Install Node.js for serving frontend static files
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g serve \
    && apt-get remove -y curl \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /root/.npm

WORKDIR /app

# Copy Python .venv (all dependencies pre-installed, no build tools)
COPY --from=python-build /app/backend/.venv /app/backend/.venv
# Copy backend source code
COPY backend/ ./backend/

# Copy built Vue frontend static files only (no node_modules)
COPY --from=frontend-build /app/frontend/dist /app/frontend/dist
COPY --from=frontend-build /app/static /app/static

EXPOSE 3000 5001

# Start Python backend + serve Vue static files
CMD ["sh", "-c", "cd /app/backend && /app/backend/.venv/bin/python run.py & serve -s /app/frontend/dist -l 3000 --no-clipboard"]
