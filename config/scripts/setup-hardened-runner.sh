#!/bin/bash
# =============================================================================
# Script de Setup do Runner Self-Hosted Hardenado
# Pipeline Hardening PoC - luan/hardened
# =============================================================================
# Este script configura um runner self-hosted com:
# - gVisor (runsc) como runtime padrão do Docker
# - Falco para monitoramento de syscalls
# - Configurações de segurança recomendadas
#
# Uso: sudo ./setup-hardened-runner.sh
# =============================================================================

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verificar se está rodando como root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script deve ser executado como root (sudo)"
   exit 1
fi

log_info "=== Iniciando setup do runner hardenado ==="

# =============================================================================
# 1. Instalar gVisor (runsc)
# =============================================================================
log_info "Instalando gVisor..."

# Adicionar repositório gVisor
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg

curl -fsSL https://gvisor.dev/archive.key | gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | tee /etc/apt/sources.list.d/gvisor.list > /dev/null

apt-get update
apt-get install -y runsc

# Verificar instalação
if runsc --version; then
    log_info "gVisor instalado com sucesso"
else
    log_error "Falha na instalação do gVisor"
    exit 1
fi

# =============================================================================
# 2. Configurar Docker para usar gVisor
# =============================================================================
log_info "Configurando Docker com gVisor..."

# Backup da configuração existente
if [ -f /etc/docker/daemon.json ]; then
    cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
    log_info "Backup criado: /etc/docker/daemon.json.bak"
fi

# Aplicar configuração hardenada
cat > /etc/docker/daemon.json << 'EOF'
{
  "runtimes": {
    "runsc": {
      "path": "/usr/local/bin/runsc",
      "runtimeArgs": [
        "--platform=ptrace",
        "--network=sandbox"
      ]
    },
    "runsc-kvm": {
      "path": "/usr/local/bin/runsc",
      "runtimeArgs": [
        "--platform=kvm"
      ]
    }
  },
  "default-runtime": "runsc",
  "features": {
    "buildkit": true
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "no-new-privileges": true,
  "icc": false,
  "live-restore": true,
  "userland-proxy": false
}
EOF

# Criar link simbólico se necessário
if [ ! -f /usr/local/bin/runsc ]; then
    ln -sf $(which runsc) /usr/local/bin/runsc
fi

# Reiniciar Docker
systemctl restart docker
log_info "Docker reiniciado com gVisor como runtime padrão"

# Testar gVisor
log_info "Testando gVisor..."
if docker run --rm --runtime=runsc hello-world; then
    log_info "gVisor funcionando corretamente"
else
    log_warn "Teste do gVisor falhou - verifique a configuração"
fi

# =============================================================================
# 3. Instalar e configurar Falco
# =============================================================================
log_info "Instalando Falco..."

# Adicionar repositório Falco
curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" | tee /etc/apt/sources.list.d/falcosecurity.list > /dev/null

apt-get update
apt-get install -y linux-headers-$(uname -r) falco

# Copiar regras customizadas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../falco/hardened-cicd-rules.yaml" ]; then
    cp "$SCRIPT_DIR/../falco/hardened-cicd-rules.yaml" /etc/falco/rules.d/
    log_info "Regras customizadas do Falco instaladas"
fi

# Habilitar e iniciar Falco
systemctl enable falco
systemctl start falco

if systemctl is-active --quiet falco; then
    log_info "Falco instalado e rodando"
else
    log_warn "Falco instalado mas não está rodando - verifique os logs"
fi

# =============================================================================
# 4. Configurações adicionais de segurança
# =============================================================================
log_info "Aplicando configurações adicionais de segurança..."

# Criar usuário runner não privilegiado se não existir
if ! id -u runner &>/dev/null; then
    useradd -m -s /bin/bash runner
    usermod -aG docker runner
    log_info "Usuário 'runner' criado"
fi

# Configurar limites de recursos
cat >> /etc/security/limits.d/runner.conf << 'EOF'
runner soft nofile 65536
runner hard nofile 65536
runner soft nproc 4096
runner hard nproc 4096
EOF

# Configurar sysctl para segurança
cat >> /etc/sysctl.d/99-runner-security.conf << 'EOF'
# Desabilitar IP forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Proteção contra SYN flood
net.ipv4.tcp_syncookies = 1

# Ignorar ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Não enviar ICMP redirects
net.ipv4.conf.all.send_redirects = 0

# Proteção contra IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Log de pacotes marcianos
net.ipv4.conf.all.log_martians = 1
EOF

sysctl -p /etc/sysctl.d/99-runner-security.conf

log_info "Configurações de sysctl aplicadas"

# =============================================================================
# 5. Verificação final
# =============================================================================
log_info "=== Verificação Final ==="

echo ""
echo "Versão do gVisor:"
runsc --version

echo ""
echo "Runtime padrão do Docker:"
docker info | grep -i runtime

echo ""
echo "Status do Falco:"
systemctl status falco --no-pager | head -5

echo ""
log_info "=== Setup concluído com sucesso! ==="
echo ""
echo "Próximos passos:"
echo "1. Configure o GitHub Actions runner usando o usuário 'runner'"
echo "2. Verifique os logs do Falco: journalctl -u falco -f"
echo "3. Teste um workflow com --runtime=runsc"
echo ""
log_warn "IMPORTANTE: Não monte /var/run/docker.sock nos containers!"
