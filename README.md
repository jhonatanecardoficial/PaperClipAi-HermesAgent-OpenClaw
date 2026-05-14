# PaperClipAi + Hermes Agent + OpenClaw

Este repositório contém a infraestrutura Docker Compose para rodar o ecossistema PaperclipAi, Hermes Agent e OpenClaw com automação de onboarding e segurança.

## Conteúdo
- `docker-compose.yml`: Orquestração dos serviços.
- `Dockerfile.paperclip` / `Dockerfile.openclaw`: Builds customizadas.
- `paperclip-entrypoint.sh`: Automação de setup e admin.
- `Cofiguracao-docker-compose.md`: Guia completo de instalação.

## Como usar
1. Clone o repositório.
2. Configure seu `.env`.
3. Execute `docker compose up --build -d`.
