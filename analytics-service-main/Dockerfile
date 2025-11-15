# =============================================================================
# Stage 1: Builder - Instalação de dependências Python
# =============================================================================
FROM python:3.11-slim AS builder

# Instala dependências do sistema necessárias para compilar pacotes Python
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Cria diretório de trabalho
WORKDIR /build

# Copia apenas requirements.txt primeiro (melhor cache)
COPY requirements.txt .

# Cria virtualenv e instala dependências
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Instala dependências Python
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# =============================================================================
# Stage 2: Final - Imagem de produção mínima
# =============================================================================
FROM python:3.11-slim

# Instala apenas wget para healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Cria usuário e grupo não-root para segurança
RUN groupadd -r -g 1001 appgroup && \
    useradd -r -u 1001 -g appgroup -m -s /sbin/nologin appuser

# Copia o virtualenv do stage anterior
COPY --from=builder --chown=appuser:appgroup /opt/venv /opt/venv

# Define PATH para usar o virtualenv
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Define diretório de trabalho
WORKDIR /app

# Copia o código da aplicação
COPY --chown=appuser:appgroup app.py .

# Muda para usuário não-root
USER appuser

# Expõe a porta da aplicação
EXPOSE 8005

# Healthcheck para verificar se o serviço está respondendo
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8005/health || exit 1

# Comando para executar a aplicação com Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:8005", "--workers", "2", "--timeout", "60", "app:app"]
