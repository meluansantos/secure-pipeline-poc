# Infra Module

Este diretório contém Infrastructure as Code (IaC).

Conforme definido no [CODEOWNERS](../.github/CODEOWNERS), alterações neste diretório requerem aprovação de:

- @luan0x73
- @infra-lead

## Segurança

Este é um diretório de alta criticidade. Todas as mudanças passam por:

- Review obrigatório de 2 aprovadores
- Scan de secrets (especialmente cuidado com credenciais AWS/GCP)
- Validação de Terraform/CloudFormation
