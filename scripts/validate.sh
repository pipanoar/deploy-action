#!/usr/bin/env bash
# Primeiro step da action: esconde o token no log e valida os inputs.
# Mostra todos os erros de uma vez e grava os valores normalizados como outputs.
#
# Variáveis lidas: INPUT_TOKEN, INPUT_PLATFORM, INPUT_CHANNEL, INPUT_ROLLOUT,
# INPUT_TARGET_APP_VERSION, INPUT_MESSAGE, INPUT_FORCE_UPDATE, INPUT_DISABLED,
# INPUT_WORKING_DIRECTORY, INPUT_SETUP_NODE, INPUT_NODE_VERSION.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# O token pode vir de um segredo (já mascarado) ou de outro lugar. Mascara de novo
# antes de qualquer outra saída, linha por linha.
token="$(trim "${INPUT_TOKEN:-}")"
if [[ -n "$token" ]]; then
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      printf '::add-mask::%s\n' "$line"
    fi
  done <<<"$token"
fi

load_inputs

errors=0
fail() {
  gh_error "$1"
  errors=$((errors + 1))
}

if [[ -z "$token" ]]; then
  fail "O input token é obrigatório. Crie um token de deploy no painel, salve como segredo do repositório (por exemplo PIPANOAR_TOKEN) e passe em token."
fi

case "$PLATFORM" in
  ios | android | both) ;;
  *) fail "platform inválido: \"$PLATFORM\". Use ios, android ou both." ;;
esac

if [[ "$CHANNEL" =~ [[:space:]] ]]; then
  fail "channel inválido: \"$CHANNEL\". O nome do canal não pode ter espaços."
fi

if ! [[ "$ROLLOUT" =~ ^[0-9]{1,3}$ ]] || ((ROLLOUT > 100)); then
  fail "rollout inválido: \"$ROLLOUT\". Use um número inteiro de 0 a 100."
elif ((ROLLOUT == 0)); then
  gh_warning "rollout 0: a release é publicada, mas nenhum aparelho recebe até você aumentar o rollout no painel."
fi

check_bool() {
  local name="$1" value="$2"
  case "$value" in
    true | false) ;;
    *) fail "$name inválido: \"$value\". Use true ou false." ;;
  esac
}
check_bool force-update "$FORCE_UPDATE"
check_bool disabled "$DISABLED"
check_bool setup-node "$SETUP_NODE"

if [[ "$SETUP_NODE" == "true" && -z "$NODE_VERSION" ]]; then
  fail "node-version vazio. Informe uma versão (por exemplo 22) ou use setup-node: false."
fi

if [[ ! -d "$WORKING_DIRECTORY" ]]; then
  fail "working-directory não encontrado: \"$WORKING_DIRECTORY\". O caminho é relativo à raiz do repositório."
else
  # A CLI só procura o config na pasta em que roda.
  config=""
  for extension in ts mts cts js mjs cjs; do
    if [[ -f "$WORKING_DIRECTORY/hot-updater.config.$extension" ]]; then
      config="$WORKING_DIRECTORY/hot-updater.config.$extension"
      break
    fi
  done
  if [[ -z "$config" ]]; then
    fail "Nenhum hot-updater.config.ts (ou .js) em \"$WORKING_DIRECTORY\". Rode npx @pipanoar/init no projeto ou ajuste working-directory para a pasta do app."
  elif ! grep -q "pipanoar" "$config"; then
    gh_warning "$config não parece usar o preset @pipanoar/hot-updater. Sem ele, a CLI não publica no Pipa no Ar."
  fi
fi

if ((errors > 0)); then
  echo "Corrija os inputs da action pipanoar/deploy-action e rode de novo." >&2
  exit 1
fi

set_output platform "$PLATFORM"
set_output channel "$CHANNEL"
set_output rollout "$ROLLOUT"
set_output force_update "$FORCE_UPDATE"
set_output disabled "$DISABLED"
set_output setup_node "$SETUP_NODE"

echo "Inputs válidos: platform=$PLATFORM channel=$CHANNEL rollout=$ROLLOUT force-update=$FORCE_UPDATE disabled=$DISABLED"
