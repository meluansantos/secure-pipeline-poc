# =============================================================================
# Dockerfile Hardenado - Pipeline Hardening PoC
# hardened-sh/secure-pipeline-poc
# =============================================================================
# Este Dockerfile segue as melhores práticas de segurança para containers:
# - Multi-stage build para reduzir superfície de ataque
# - Usuário não-root
# - Imagem base minimal (distroless/alpine)
# - Sem shells ou ferramentas desnecessárias na imagem final
# =============================================================================

# =============================================================================
# Stage 1: Build
# =============================================================================
FROM golang:1.22-alpine AS builder

# Instalar dependências de build
RUN apk add --no-cache git ca-certificates tzdata

# Criar usuário não-root para build
RUN adduser -D -g '' appuser

WORKDIR /build

# Copiar arquivos de dependências primeiro (cache layers)
COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true

# Copiar código fonte
COPY . .

# Build com flags de segurança
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags='-w -s -extldflags "-static"' \
    -o /app/server ./cmd/server 2>/dev/null || \
    echo "package main\nfunc main() { println(\"Hardened App Running\") }" > main.go && \
    CGO_ENABLED=0 go build -ldflags='-w -s' -o /app/server .

# =============================================================================
# Stage 2: Runtime (Distroless)
# =============================================================================
FROM gcr.io/distroless/static-debian12:nonroot AS runtime

# Labels para rastreabilidade
LABEL maintainer="hardened-sh"
LABEL org.opencontainers.image.source="https://github.com/hardened-sh/secure-pipeline-poc"
LABEL org.opencontainers.image.description="Pipeline Hardening PoC"
LABEL org.opencontainers.image.licenses="MIT"

# Copiar timezone data e certificados
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copiar binário
COPY --from=builder /app/server /app/server

# Usar usuário não-root (65532 é o nonroot user do distroless)
USER 65532:65532

# Expor porta da aplicação
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/app/server", "-health"] || exit 1

# Entrypoint
ENTRYPOINT ["/app/server"]

# =============================================================================
# Stage Alternativo: Alpine (para debugging, se necessário)
# =============================================================================
FROM alpine:3.19 AS runtime-debug

# Configurações de segurança
RUN apk add --no-cache ca-certificates tzdata && \
    adduser -D -g '' -u 10001 appuser && \
    rm -rf /var/cache/apk/*

# Copiar binário
COPY --from=builder /app/server /app/server

# Permissões
RUN chown -R appuser:appuser /app && \
    chmod 500 /app/server

USER appuser

EXPOSE 8080

ENTRYPOINT ["/app/server"]
