#!/usr/bin/env bash
# Publica a release com a CLI oficial do hot-updater (npx hot-updater deploy),
# uma plataforma por vez, e escreve o resumo do job.
#
# Variáveis lidas: PIPANOAR_TOKEN (repassado à CLI), INPUT_PLATFORM,
# INPUT_CHANNEL, INPUT_ROLLOUT, INPUT_TARGET_APP_VERSION, INPUT_MESSAGE,
# INPUT_FORCE_UPDATE, INPUT_DISABLED, INPUT_WORKING_DIRECTORY e
# GITHUB_STEP_SUMMARY (opcional).
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PANEL_URL="https://app.pipanoar.scuderiatech.com.br"

load_inputs

PIPANOAR_TOKEN="$(trim "${PIPANOAR_TOKEN:-}")"
if [[ -z "$PIPANOAR_TOKEN" ]]; then
  gh_error "Token de deploy vazio. Passe o segredo no input token."
  exit 1
fi
export PIPANOAR_TOKEN

cd "$WORKING_DIRECTORY"

# --no: falha em vez de baixar outra versão da CLI do npm. A versão usada é a
# que está no lockfile do projeto.
if ! cli_version="$(npx --no hot-updater --version 2>/dev/null)"; then
  gh_error "A CLI do hot-updater não está instalada em \"$WORKING_DIRECTORY\". Adicione hot-updater e @pipanoar/hot-updater às devDependencies do app."
  exit 1
fi
echo "CLI do hot-updater: $cli_version"

# Argumentos comuns às duas plataformas.
common=(-c "$CHANNEL" -r "$ROLLOUT")
[[ -z "$TARGET_APP_VERSION" ]] || common+=(-t "$TARGET_APP_VERSION")
[[ -z "$MESSAGE" ]] || common+=(-m "$MESSAGE")
[[ "$FORCE_UPDATE" != "true" ]] || common+=(-f)
[[ "$DISABLED" != "true" ]] || common+=(-d)

# Resultado de cada plataforma, para o resumo.
results=()
exit_code=0
for platform in $(platforms_for "$PLATFORM"); do
  if ((exit_code != 0)); then
    results+=("$platform:não executado")
    continue
  fi
  args=(deploy -p "$platform" "${common[@]}")
  echo "::group::Deploy $(platform_label "$platform")"
  echo "+ npx hot-updater ${args[*]}"
  status=0
  npx --no hot-updater "${args[@]}" || status=$?
  echo "::endgroup::"
  if ((status == 0)); then
    results+=("$platform:publicado")
  else
    results+=("$platform:falhou")
    gh_error "O deploy de $(platform_label "$platform") falhou (código $status). Veja o log do step."
    exit_code=$status
  fi
done

# Escapa o | para não quebrar a tabela em Markdown.
cell() {
  local value="$1"
  printf '%s' "${value//|/\\|}"
}

write_summary() {
  local target="${TARGET_APP_VERSION:-automática}"
  echo "### Deploy OTA no Pipa no Ar"
  echo
  echo "| Plataforma | Canal | Rollout | Versão alvo | Resultado |"
  echo "|---|---|---|---|---|"
  local entry
  for entry in "${results[@]}"; do
    echo "| $(platform_label "${entry%%:*}") | $(cell "$CHANNEL") | $ROLLOUT% | $(cell "$target") | ${entry#*:} |"
  done
  echo
  [[ "$FORCE_UPDATE" != "true" ]] || echo "- Atualização forçada: o app recarrega assim que baixar."
  [[ "$DISABLED" != "true" ]] || echo "- Release criada desativada. Ative pelo painel quando quiser liberar."
  echo "- Acompanhe a release e os crashes no [painel do Pipa no Ar]($PANEL_URL)."
}

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  write_summary >>"$GITHUB_STEP_SUMMARY"
fi

exit "$exit_code"
