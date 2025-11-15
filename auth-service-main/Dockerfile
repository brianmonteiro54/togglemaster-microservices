# =============================================================================
# Stage 1: Builder - Compilação da aplicação Go
# =============================================================================
FROM golang:1.25-alpine AS builder

# Instala certificados SSL e ferramentas básicas
RUN apk add --no-cache ca-certificates git

# Define o diretório de trabalho
WORKDIR /build

# Copia todo o código-fonte
COPY . .

# Download das dependências e gera go.sum
RUN go mod download && go mod tidy

# Compila a aplicação com otimizações
# CGO_ENABLED=0: Gera binário estático sem dependências C
# -ldflags="-w -s": Remove informações de debug (reduz tamanho)
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o auth-service .

# =============================================================================
# Stage 2: Final - Imagem de produção mínima
# =============================================================================
FROM alpine:3.22

# Instala apenas certificados SSL (necessário para HTTPS)
RUN apk add --no-cache ca-certificates tzdata wget

# Cria usuário e grupo não-root para segurança
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Define diretório de trabalho
WORKDIR /app

# Copia o binário compilado do stage anterior
# Define o usuário correto como dono do arquivo
COPY --from=builder --chown=appuser:appgroup /build/auth-service .

# Copia os scripts SQL de inicialização se necessário
COPY --chown=appuser:appgroup db/ ./db/

# Muda para usuário não-root
USER appuser

# Expõe a porta da aplicação
EXPOSE 8001

# Healthcheck para verificar se o serviço está respondendo
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8001/health || exit 1

# Comando para executar a aplicação
CMD ["./auth-service"]
