# 🔒 Pipeline Hardening PoC

> **Hardening CI/CD – Diagnóstico e Contramedidas Pós-Pentest**

Este repositório é uma Proof of Concept (PoC) baseada no artigo publicado em [hardened.com.br](https://hardened.com.br), demonstrando técnicas de hardening para pipelines CI/CD após um assessment de segurança.

⚠️ **Aviso**: Este material contém técnicas de exploração e hardening avançadas. Use-as apenas em ambientes autorizados.

## 📖 O Contexto

**01:13 h – O ponto de ruptura**

Durante o assessment, o pipeline disparou às 01:13 h e entregou um binário que nunca passou pelo processo de build. O runner, configurado com `docker.sock` montado e permissões de root, permitiu que o invasor obtivesse acesso ao host, realizasse lateral movement dentro da VPC e começasse a exfiltrar credenciais. O blast radius atingiu todo o cluster de produção.

## 🛡️ Contramedidas Implementadas

### 1. Controle de Versão à Prova de Força

**Problema**: Force-push e admin override permitem reescrever a história da branch main, removendo commits maliciosos e apagando evidências.

**Solução Implementada**:

- [CODEOWNERS](.github/CODEOWNERS) definido para diretórios críticos
- Política de branch que exige commits assinados (GPG/SSH)
- Review obrigatório de dois aprovadores
- `enforce_admins: true` impede sobrescritas mesmo por administradores

```yaml
# .github/workflows/branch-protect.yml
required_approving_review_count: 2
enforce_admins: true
require_signed_commits: true
```

### 2. Eliminação de Segredos Estáticos com OIDC

**Problema**: Variáveis como `AWS_ACCESS_KEY` são copiadas para o workspace durante o build, permitindo credential reuse.

**Solução Implementada**:

- OpenID Connect (OIDC) para credenciais temporárias
- Gitleaks integrado ao CI/CD para bloquear novos secrets

```yaml
# Usando OIDC ao invés de secrets estáticos
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/GitHubActionsRole
    aws-region: us-east-1
```

### 3. Proveniência e Integridade (SBOM + Cosign)

**Problema**: Um atacante pode modificar camadas intermediárias sem alterar o hash da imagem final.

**Solução Implementada**:

- SBOM gerado com **Syft** listando todas as dependências
- Assinatura com **Cosign** (keyless via OIDC)
- Atestação do SBOM anexada à imagem

```bash
# Gerar SBOM
syft packages ghcr.io/hardened-sh/secure-pipeline-poc:$SHA -o spdx-json > sbom.spdx.json

# Assinar imagem
cosign sign --yes ghcr.io/hardened-sh/secure-pipeline-poc:$SHA

# Atestar SBOM
cosign attest --yes --type spdxjson --predicate sbom.spdx.json ghcr.io/hardened-sh/secure-pipeline-poc:$SHA
```

### 4. Isolamento de Runtime (gVisor + Falco)

**Problema**: `docker.sock` montado concede controle total sobre o daemon host – clássico container escape.

**Solução Implementada**:

- **gVisor (runsc)** como runtime padrão – user-space kernel que intercepta syscalls
- **Falco** para monitoramento de eventos críticos em tempo real

```json
// /etc/docker/daemon.json
{
  "runtimes": {
    "runsc": { "path": "/usr/local/bin/runsc" }
  },
  "default-runtime": "runsc"
}
```

## 📁 Estrutura do Repositório

```yaml
pipeline-hardening/
├── .github/
│   ├── CODEOWNERS                    # Controle de acesso por diretório
│   └── workflows/
│       ├── branch-protect.yml        # Proteção automática de branch
│       ├── secret-scan.yml           # Scan de secrets com Gitleaks
│       ├── build-sign.yml            # Build + SBOM + Cosign
│       └── secure-build.yml          # Build com gVisor
├── config/
│   ├── docker/
│   │   └── daemon.json               # Config do Docker com gVisor
│   ├── falco/
│   │   └── hardened-cicd-rules.yaml  # Regras customizadas do Falco
│   └── scripts/
│       └── setup-hardened-runner.sh  # Setup do runner self-hosted
├── cmd/
│   └── server/
│       └── main.go                   # Aplicação de exemplo
├── Dockerfile                        # Multi-stage hardenado
├── go.mod                            # Módulo Go
└── README.md                         # Esta documentação
```

## 🚀 Como Usar

### 1. Fork e Clone

```bash
git clone https://github.com/hardened-sh/secure-pipeline-poc.git
cd secure-pipeline-poc
```

### 2. Configurar Secrets no GitHub

Vá em **Settings > Secrets and variables > Actions** e adicione:

| Secret | Descrição |
| ------ | --------- |
| `AWS_ACCOUNT_ID` | ID da conta AWS (para OIDC) |
| `COSIGN_KEY` | Chave privada do Cosign (opcional - keyless preferido) |
| `COSIGN_PWD` | Senha da chave Cosign (se usar chave) |

### 3. Configurar OIDC na AWS (Recomendado)

```bash
# Criar Identity Provider no IAM
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Criar Role com trust policy
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:hardened-sh/secure-pipeline-poc:*"
      }
    }
  }]
}
EOF

aws iam create-role --role-name GitHubActionsRole --assume-role-policy-document file://trust-policy.json
```

### 4. Setup do Runner Self-Hosted (para gVisor)

```bash
# No servidor do runner
sudo ./config/scripts/setup-hardened-runner.sh

# Verificar gVisor
docker run --rm --runtime=runsc hello-world

# Verificar Falco
sudo systemctl status falco
journalctl -u falco -f
```

### 5. Verificar Assinatura de Imagem

```bash
# Verificar assinatura
cosign verify \
  --certificate-identity-regexp="https://github.com/hardened-sh/secure-pipeline-poc.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/hardened-sh/secure-pipeline-poc:main

# Verificar SBOM atestado
cosign verify-attestation \
  --type spdxjson \
  --certificate-identity-regexp="https://github.com/hardened-sh/secure-pipeline-poc.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/hardened-sh/secure-pipeline-poc:main
```

## 🔍 Workflows

### branch-protect.yml

Aplica automaticamente proteções à branch main toda semana:

- Status checks obrigatórios
- 2 aprovadores mínimos
- Commits assinados
- Bloqueio de force-push

### secret-scan.yml

Executa em todo push/PR:

- Scan completo com Gitleaks
- Upload de resultados SARIF
- Bloqueio do PR se secrets forem encontrados

### build-sign.yml

Pipeline completo de build seguro:

1. Checkout do código
2. Configuração de credenciais via OIDC
3. Build e push da imagem
4. Geração de SBOM (SPDX + CycloneDX)
5. Assinatura com Cosign (keyless)
6. Atestação do SBOM
7. Scan de vulnerabilidades com Trivy

### secure-build.yml

Build em ambiente isolado:

- Container com `--runtime=runsc`
- Sem privilégios (`no-new-privileges`)
- Capabilities dropadas
- Filesystem read-only

## 📊 Regras do Falco

O arquivo `config/falco/hardened-cicd-rules.yaml` detecta:

| Regra | Severidade | Descrição |
| ----- | ---------- | --------- |
| Container Escape via Docker Socket | CRITICAL | Uso de docker CLI dentro de container |
| Mount of Docker Socket | CRITICAL | Acesso a /var/run/docker.sock |
| Privilege Escalation | WARNING | Uso de su/sudo/chmod +s |
| Reverse Shell | CRITICAL | Padrões de reverse shell |
| Write to Sensitive Paths | CRITICAL | Escrita em .github/workflows |
| Credential Access | WARNING | Acesso a .aws/credentials, .ssh/* |
| Kernel Module Load | CRITICAL | Tentativa de carregar módulos |

## 🧪 Testando Localmente

```bash
# Build da imagem
docker build -t hardened-sh/secure-pipeline-poc:local .

# Executar com gVisor (se disponível)
docker run --rm --runtime=runsc -p 8080:8080 hardened-sh/secure-pipeline-poc:local

# Testar endpoints
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/info
```

## 📚 Referências

- [Artigo Original - hardened](https://hardened.com.br)
- [gVisor Documentation](https://gvisor.dev/docs/)
- [Falco](https://falco.org/)
- [Sigstore/Cosign](https://docs.sigstore.dev/)
- [Syft](https://github.com/anchore/syft)
- [Gitleaks](https://github.com/gitleaks/gitleaks)
- [SLSA Framework](https://slsa.dev/)

## 🔐 Defesa em Profundidade

> O projeto Hardened demonstra que a única maneira de reduzir o risco é eliminar a negligência: **controle de acesso rigoroso**, **credenciais transitórias**, **assinatura de artefatos** e **sandbox de kernel**. Cada camada adicionada diminui a superfície de ataque e aumenta a confiança na cadeia de suprimentos.

## 📄 Licença

MIT License - Veja [LICENSE](LICENSE) para detalhes.

---

**Autor**: [@hardened-sh](https://github.com/hardened-sh)  
**Blog**: [hardened.com.br](https://hardened.com.br)
