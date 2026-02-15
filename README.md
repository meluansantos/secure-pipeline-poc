# 🔒 Pipeline Hardening PoC

Este repositório é um **laboratório de estudos** focado em segurança de infraestrutura e CI/CD. O objetivo aqui foi sair da superfície e entender como blindar uma esteira de build contra ataques reais de *Supply Chain*.

⚠️ **Nota de estudo**: Este projeto contém configurações propositalmente complexas para testar limites de hardening.

## 🧠 Por que este lab?

A maioria dos pipelines por aí é um "buraco negro" de segurança: runners com permissão de root, segredos expostos em variáveis de ambiente e binários que ninguém sabe de onde vieram.

Neste lab, eu me forcei a resolver 4 dores que tiram o sono de qualquer engenheiro que se preocupa com o sistema além da interface:

### 1. O fim do "Force-Push" e da bagunça na Main

Confiar apenas na boa vontade do time não é estratégia de segurança.

* **A dor:** Alguém apagar o histórico de commits maliciosos ou pular o build.
* **O que implementei:** Proteção de branch via código, exigindo commits assinados e aprovação dupla obrigatória. Nem admin passa sem revisão.

### 2. Chega de "AWS_ACCESS_KEY" estática

Segredo em variável de ambiente é um desastre esperando para acontecer.

* **A dor:** Se o runner for invadido, suas chaves da AWS já eram.
* **O que implementei:** Autenticação via **OIDC**. O GitHub Actions conversa com a AWS e recebe uma credencial temporária que expira em minutos. Sem chaves fixas, sem vazamentos permanentes.

### 3. "Quem buildou isso?" (SBOM + Cosign)

Garantir a integridade do que vai para produção.

* **A dor:** Um atacante pode trocar o binário dentro do container sem mudar a tag da imagem.
* **O que implementei:** Geração de **SBOM (Syft)** para saber exatamente cada lib que está lá dentro e assinatura digital da imagem com **Cosign**. Se a assinatura não bater, o deploy nem começa.

### 4. Isolamento Real: gVisor + Falco

Parar de confiar cegamente no isolamento padrão do Docker.

* **A dor:** O clássico *Container Escape* via `docker.sock`.
* **O que implementei:** * **gVisor (runsc):** Um kernel em user-space que intercepta syscalls. Se o atacante tentar algo no kernel do host, ele bate no muro do gVisor.
* **Falco:** Monitoramento de comportamento estranho em tempo real (ex: alguém tentando abrir um reverse shell no build).



---

## 📁 O que tem aqui dentro?

```text
.
├── .github/workflows/       # Onde a mágica do hardening acontece
├── config/                  # Configurações de runtime (gVisor e Falco)
├── cmd/server/              # Um servidor simples em Go para testar a esteira
├── Dockerfile               # Build multi-stage focado em reduzir superfície de ataque
└── go.mod                   # Gestão de dependências

```

## 🛠️ Como testar as contra-medidas

### 1. Verificando a Assinatura (Cosign)

Para garantir que a imagem não foi alterada após o build:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/meluansantos/secure-pipeline-poc.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/meluansantos/secure-pipeline-poc:main

```

### 2. Validando o isolamento do Runtime

Se você rodar o runner self-hosted configurado, o container deve rodar sob o kernel do gVisor:

```bash
docker run --rm --runtime=runsc hello-world

```

---

## 📚 Aprendizados e Referências

Este projeto foi construído estudando os fundamentos de:

* [gVisor Documentation](https://gvisor.dev/docs/) - Isolamento de kernel.
* [Sigstore/Cosign](https://docs.sigstore.dev/) - Assinatura de artefatos.
* [SLSA Framework](https://slsa.dev/) - Níveis de segurança para cadeias de suprimento.

---

**Laboratório mantido por Luan Rodrigues** [luansantos.net/lab](https://luansantos.net/lab)
