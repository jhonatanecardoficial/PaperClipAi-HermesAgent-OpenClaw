#!/bin/sh
set -e

# ──────────────────────────────────────────────────────────────
# paperclip-entrypoint.sh
# Wrapper que roda ANTES do entrypoint oficial do Paperclip.
# Garante que:
#   1. As permissões do volume /paperclip estejam corretas
#   2. O onboarding (quickstart) rode automaticamente se necessário
#   3. O primeiro admin (CEO) seja criado com um invite URL
# ──────────────────────────────────────────────────────────────

CONFIG_FILE="/paperclip/instances/default/config.json"
ONBOARD_MARKER="/paperclip/instances/default/.onboarded"

# ── 1. Corrigir permissões do volume ──────────────────────────
echo "[entrypoint] Corrigindo permissões do volume /paperclip..."
chown -R node:node /paperclip

# ── 2. Onboarding automático (quickstart) ─────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[entrypoint] Configuração não encontrada. Executando onboarding automático (quickstart)..."

    # Roda o onboard como node user com input automático (seleciona Quickstart + No para auto-start)
    gosu node sh -c '
        # Cria a estrutura mínima necessária
        mkdir -p /paperclip/instances/default

        # Executa onboard em modo não-interativo via expect-like stdin
        printf "\n\n" | node cli/node_modules/tsx/dist/cli.mjs cli/src/index.ts onboard 2>&1 || true
    '

    # Corrigir permissões novamente após onboarding
    chown -R node:node /paperclip

    echo "[entrypoint] Onboarding concluído."
fi

# ── 3. Bootstrap CEO (primeiro admin) ─────────────────────────
if [ -f "$CONFIG_FILE" ] && [ ! -f "$ONBOARD_MARKER" ]; then
    echo "[entrypoint] Gerando invite do primeiro admin (CEO)..."

    INVITE_OUTPUT=$(gosu node node cli/node_modules/tsx/dist/cli.mjs cli/src/index.ts auth bootstrap-ceo 2>&1 || true)

    # Extrair e exibir o URL do invite
    INVITE_URL=$(echo "$INVITE_OUTPUT" | grep -oP 'http[s]?://[^\s]+/invite/[^\s]+' || true)

    if [ -n "$INVITE_URL" ]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║  🔑 INVITE DO ADMIN (CEO) GERADO COM SUCESSO!              ║"
        echo "╠══════════════════════════════════════════════════════════════╣"
        echo "║                                                            ║"
        echo "║  Acesse este link no navegador para criar seu admin:       ║"
        echo "║  $INVITE_URL"
        echo "║                                                            ║"
        echo "║  ⚠ Este link expira em 3 dias.                            ║"
        echo "║  Para gerar novo: docker compose exec paperclip            ║"
        echo "║    pnpm paperclipai auth bootstrap-ceo                     ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
    else
        echo "[entrypoint] AVISO: Não foi possível extrair o invite URL."
        echo "[entrypoint] Execute manualmente após o container iniciar:"
        echo "    docker compose exec paperclip pnpm paperclipai auth bootstrap-ceo"
    fi

    # Marcar como onboarded para não repetir
    gosu node touch "$ONBOARD_MARKER"
fi

# ── 4. Delegar para o entrypoint original ─────────────────────
echo "[entrypoint] Iniciando Paperclip..."
exec /usr/local/bin/docker-entrypoint.sh "$@"
