# Configuração Docker Compose para PaperClipAi, Hermes Agente e OpenClaw

Este documento descreve como configurar e executar o PaperClipAi, Hermes Agente e OpenClaw usando Docker Compose. A configuração constrói as imagens a partir dos repositórios oficiais, automatiza o onboarding do Paperclip e gera o primeiro admin automaticamente.

## Pré-requisitos

Antes de começar, certifique-se de ter o seguinte instalado:

*   **Docker:** [Instruções de instalação](https://docs.docker.com/get-docker/)
*   **Docker Compose:** Geralmente vem junto com a instalação do Docker Desktop. Se não, [instale-o separadamente](https://docs.docker.com/compose/install/)
*   **Git:** Para clonar os repositórios.

### Requisitos de Hardware

> ⚠️ A build do OpenClaw é **muito pesada** e exige recursos significativos:
> - **RAM mínima:** 8GB livres para o Docker (16GB+ recomendado)
> - **Disco:** ~10GB livres para imagens e cache de build
> - **Docker Memory Limit:** Certifique-se de que o Docker está configurado com pelo menos 8GB de RAM (Docker Desktop → Settings → Resources → Memory)

## Estrutura do Projeto

```
.
├── docker-compose.yml
├── Dockerfile.paperclip
├── Dockerfile.openclaw           (copiado de openclaw/Dockerfile)
├── paperclip-entrypoint.sh       (wrapper que automatiza onboarding + admin)
├── .env
├── workspace/                    (diretório para o OpenClaw acessar arquivos do host)
├── paperclipai/                  (repositório clonado do PaperClipAi)
├── hermes-agent/                 (repositório clonado do Hermes Agente)
└── openclaw/                     (repositório clonado do OpenClaw)
```

## Passos para Configuração e Execução

### 1. Clonar os Repositórios

```bash
git clone https://github.com/paperclipai/paperclip.git paperclipai
git clone https://github.com/NousResearch/hermes-agent.git hermes-agent
git clone https://github.com/openclaw/openclaw.git openclaw
```

### 2. Copiar o Dockerfile do OpenClaw

> **IMPORTANTE:** O `Dockerfile.openclaw` deve ser **copiado diretamente** do repositório oficial. Nunca o edite manualmente.

```bash
cp openclaw/Dockerfile Dockerfile.openclaw
```

### 3. Criar o Diretório Workspace

```bash
mkdir -p workspace
```

### 4. Configurar Variáveis de Ambiente

Crie um arquivo `.env` na raiz do seu projeto:

```dotenv
# Sua chave da API OpenAI (ou de outro provedor)
OPENAI_API_KEY="SUA_CHAVE_OPENAI_AQUI"

# Uma chave secreta para autenticação do Paperclip (gere com: openssl rand -base64 32)
BETTER_AUTH_SECRET="SUA_CHAVE_SECRETA_AQUI"

# URL pública do Paperclip
PAPERCLIP_PUBLIC_URL="http://localhost:8080"

# Opcional: Chave da API do OpenClaw para plugins externos
# OPENCLAW_API_KEY="SUA_CHAVE_OPENCLAW_AQUI"
```

**Importante:** Substitua `SUA_CHAVE_OPENAI_AQUI` e `SUA_CHAVE_SECRETA_AQUI` por valores reais.

### 5. Executar o Docker Compose

```bash
docker compose up --build -d
```

*   `--build`: Garante que as imagens sejam construídas a partir dos Dockerfiles locais.
*   `-d`: Executa os serviços em segundo plano (detached mode).

> **⚠️ Se a build do OpenClaw travar ou der OOM (Killed):**
>
> **Opção 1 — Buildar apenas o OpenClaw primeiro (recomendado):**
> ```bash
> DOCKER_BUILDKIT=1 docker compose build --no-cache openclaw
> docker compose up -d
> ```
>
> **Opção 2 — Aumentar recursos do Docker:**
> No Docker Desktop: Settings → Resources → Memory → 10GB+
>
> **Opção 3 — Usar a imagem oficial pré-compilada (mais rápido):**
> Substitua o bloco `openclaw` no `docker-compose.yml` por:
> ```yaml
> openclaw:
>   image: ghcr.io/openclaw/openclaw:latest
>   ports:
>     - "9000:18789"
>   command: ["node", "openclaw.mjs", "gateway", "--allow-unconfigured", "--bind", "lan"]
>   environment:
>     NODE_ENV: "production"
>   volumes:
>     - ./workspace:/workspace
>     - openclaw-data:/home/node/.openclaw
>   networks:
>     - agents_net
> ```

### 6. Obter o Link do Admin (Primeira Vez)

Na **primeira execução**, o Paperclip roda automaticamente:
1. ✅ Correção de permissões do volume
2. ✅ Onboarding (quickstart) — configura banco, auth, storage
3. ✅ Geração do invite do primeiro admin (CEO)

Para ver o link do invite, verifique os logs:

```bash
docker compose logs paperclip | grep "invite"
```

Você verá algo como:

```
║  http://localhost:8080/invite/pcp_bootstrap_XXXXXXXXXXXX
```

**Abra este link no navegador** para criar sua conta admin. O link expira em 3 dias.

> Se o link expirar, gere um novo:
> ```bash
> docker compose exec paperclip pnpm paperclipai auth bootstrap-ceo
> ```

### 7. Verificar o Status dos Serviços

```bash
docker compose ps
```

Para ver os logs de um serviço específico:

```bash
docker compose logs -f paperclip
docker compose logs -f openclaw
```

### 8. Acessar as Interfaces

*   **PaperClipAi:** `http://localhost:8080`
*   **Hermes Agente:** `http://localhost:7000` (API)
*   **OpenClaw:** `http://localhost:9000` (Gateway API)

## Arquivos do Projeto

### `paperclip-entrypoint.sh` — Entrypoint Wrapper

Este script roda **antes** do entrypoint oficial do Paperclip e automatiza:

| Etapa | O que faz | Quando roda |
|-------|-----------|-------------|
| 1. Permissões | `chown -R node:node /paperclip` | Sempre |
| 2. Onboarding | `paperclipai onboard` (quickstart) | Apenas se `config.json` não existir |
| 3. Bootstrap CEO | `paperclipai auth bootstrap-ceo` | Apenas na primeira vez (usa marker `.onboarded`) |
| 4. Delegação | Passa controle ao entrypoint original | Sempre |

### `Dockerfile.paperclip`

```dockerfile
FROM node:lts-trixie-slim AS base
ARG USER_UID=1000
ARG USER_GID=1000
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates gosu curl gh git wget ripgrep python3 \
  && rm -rf /var/lib/apt/lists/* \
  && corepack enable

RUN usermod -u $USER_UID --non-unique node \
  && groupmod -g $USER_GID --non-unique node \
  && usermod -g $USER_GID -d /paperclip node

FROM base AS deps
WORKDIR /app
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml .npmrc ./
COPY cli/package.json cli/
COPY server/package.json server/
COPY ui/package.json ui/
COPY packages/shared/package.json packages/shared/
COPY packages/db/package.json packages/db/
COPY packages/adapter-utils/package.json packages/adapter-utils/
COPY packages/mcp-server/package.json packages/mcp-server/
COPY packages/adapters/acpx-local/package.json packages/adapters/acpx-local/
COPY packages/adapters/claude-local/package.json packages/adapters/claude-local/
COPY packages/adapters/codex-local/package.json packages/adapters/codex-local/
COPY packages/adapters/cursor-cloud/package.json packages/adapters/cursor-cloud/
COPY packages/adapters/cursor-local/package.json packages/adapters/cursor-local/
COPY packages/adapters/gemini-local/package.json packages/adapters/gemini-local/
COPY packages/adapters/openclaw-gateway/package.json packages/adapters/openclaw-gateway/
COPY packages/adapters/opencode-local/package.json packages/adapters/opencode-local/
COPY packages/adapters/pi-local/package.json packages/adapters/pi-local/
COPY packages/plugins/sdk/package.json packages/plugins/sdk/
COPY --parents packages/plugins/sandbox-providers/./*/package.json packages/plugins/sandbox-providers/
COPY packages/plugins/paperclip-plugin-fake-sandbox/package.json packages/plugins/paperclip-plugin-fake-sandbox/
COPY packages/plugins/plugin-llm-wiki/package.json packages/plugins/plugin-llm-wiki/
COPY patches/ patches/

RUN pnpm install --frozen-lockfile

FROM base AS build
WORKDIR /app
COPY --from=deps /app /app
COPY . .
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/plugin-sdk build
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js || (echo "ERROR: server build output missing" && exit 1)

FROM base AS production
ARG USER_UID=1000
ARG USER_GID=1000
WORKDIR /app
COPY --chown=node:node --from=build /app /app
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai \
  && apt-get update \
  && apt-get install -y --no-install-recommends openssh-client jq \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /paperclip \
  && chown node:node /paperclip

COPY scripts/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV NODE_ENV=production \
  HOME=/paperclip \
  HOST=0.0.0.0 \
  PORT=3100 \
  SERVE_UI=true \
  PAPERCLIP_HOME=/paperclip \
  PAPERCLIP_INSTANCE_ID=default \
  USER_UID=${USER_UID} \
  USER_GID=${USER_GID} \
  PAPERCLIP_CONFIG=/paperclip/instances/default/config.json \
  PAPERCLIP_DEPLOYMENT_MODE=authenticated \
  PAPERCLIP_DEPLOYMENT_EXPOSURE=private \
  OPENCODE_ALLOW_ALL_MODELS=true

VOLUME ["/paperclip"]
EXPOSE 3100

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "--import", "./server/node_modules/tsx/dist/loader.mjs", "server/dist/index.js"]
```

### `Dockerfile.openclaw`

> Copiado diretamente de `openclaw/Dockerfile`. Não editar manualmente.
> Para atualizar: `cp openclaw/Dockerfile Dockerfile.openclaw`

## Observações Importantes

*   **Volumes:** Os volumes `pgdata`, `paperclip-data`, `hermes-data` e `openclaw-data` persistem dados entre reinicializações. Para remover: `docker volume rm <nome>`.
*   **Rede:** Todos os serviços estão na rede `agents_net` para comunicação interna via nomes de serviço.
*   **Porta do PostgreSQL:** Mapeada para `5434` no host para evitar conflito com PostgreSQL local. Internamente os containers usam `db:5432`.
*   **Porta do OpenClaw:** O gateway escuta na porta `18789` internamente. O compose mapeia `9000:18789`.
*   **USER node:** O Dockerfile oficial do OpenClaw roda como `USER node`. O volume de dados é `/home/node/.openclaw`.
*   **Onboarding Automático:** O script `paperclip-entrypoint.sh` automatiza todo o setup inicial. Na primeira execução, apenas verifique os logs para obter o link do admin.

## Troubleshooting

### Build do OpenClaw trava / "Killed"
- **Causa:** O step `pnpm build:docker` usa `NODE_OPTIONS=--max-old-space-size=8192` (8GB de heap).
- **Solução:** Aumente a memória do Docker para 10GB+ ou use a imagem pré-compilada.

### Porta já em uso (ex: `5432`, `5433`)
- **Causa:** Outro serviço (PostgreSQL local) já usa a porta.
- **Solução:** Altere a porta no `docker-compose.yml` (ex: `"5434:5432"`). A porta interna (5432) não muda.

### Erro "EACCES: permission denied" no Paperclip
- **Causa:** Volume `/paperclip` criado com permissões de root.
- **Solução:** Já corrigido automaticamente pelo `paperclip-entrypoint.sh`.

### Erro "matrix-sdk-crypto native addon missing"
- **Causa:** Download do addon nativo falhou.
- **Solução:** O Dockerfile tem retry automático (5 tentativas). Verifique sua conexão.

### OpenClaw não responde na porta 9000
- **Causa:** O gateway escuta em `127.0.0.1:18789` por padrão.
- **Solução:** Use `--bind lan` no comando (já configurado).

### "Instance setup required" no Paperclip
- **Causa:** Onboarding não foi executado.
- **Solução:** Já corrigido automaticamente pelo `paperclip-entrypoint.sh`. Se persistir:
  ```bash
  docker compose exec paperclip pnpm paperclipai onboard
  docker compose exec paperclip pnpm paperclipai auth bootstrap-ceo
  docker compose restart paperclip
  ```
