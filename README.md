# 🔒Pipeline Hardening PoC

PoC que montei pra estudar hardening de pipeline CI/CD. Comecei depois de ler sobre o caso do **Codecov** e ficar incomodado com o tanto de pipeline que eu já tinha subido sem pensar direito em supply chain. Runner com `root`, secret estática colada no repo, zero verificação de integridade, o básico do que não deveria existir.

O repositório não é um projeto de produção. É um lab onde eu fui testando cada contramedida separadamente até entender o que realmente faz diferença e o que é teatro de segurança.

## 🤔 O que tem aqui

🛡️ **Branch protection** configurada via workflow agendado, não na mão. Commits assinados, 2 approvals obrigatórios, enforce em admin. Parece exagero, mas `force-push` na `main` é literalmente como um atacante apaga evidência depois de injetar código.

🔑 O build usa **OIDC** pra autenticar na AWS em vez de `AWS_ACCESS_KEY` fixa. O runner pega um JWT do GitHub, troca por credencial temporária com escopo limitado. Se o runner for comprometido, a credencial morre em minutos.

📦 Pra integridade dos artefatos: **SBOM** gerado com `Syft` (SPDX + CycloneDX) e assinatura keyless com `Cosign` via **Sigstore**. Dá pra qualquer um verificar que a imagem saiu desse repo e que ninguém trocou camada entre o build e o deploy.

🧱 A parte de runtime foi a que mais apanhei. O **gVisor** (`runsc`) coloca um kernel em user-space entre o container e o host, o container nunca faz syscall direto no kernel real. O **Falco** fica em cima monitorando comportamento suspeito (reverse shell, acesso ao `docker.sock`, `ptrace`, etc). As regras customizadas tão em `config/falco/`.

```
.github/workflows/    -> build, scan de secrets, branch protection
config/               -> regras Falco, scripts de setup do runner
cmd/server/           -> servidor Go básico pra ter algo pra buildar
Dockerfile            -> multi-stage, distroless, non-root
```

## Testando

Verificar assinatura:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/meluansantos/secure-pipeline-poc.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/meluansantos/secure-pipeline-poc:main
```

gVisor (precisa de runner self-hosted):

```bash
docker run --rm --runtime=runsc hello-world
```

## Referências

* [gVisor docs](https://gvisor.dev/docs/)
* [Sigstore/Cosign](https://docs.sigstore.dev/)
* [SLSA Framework](https://slsa.dev/)
* [Codecov incident](https://about.codecov.io/security-update/)

---

Mantido por Luan Rodrigues — [luansantos.net/lab](https://luansantos.net/lab)
