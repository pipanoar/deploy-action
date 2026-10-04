#!/usr/bin/env bash
# Decide como instalar as dependências do projeto. Não instala nada: só grava
# os outputs que os próximos steps usam.
#
# Variáveis lidas: INPUT_INSTALL_COMMAND, INPUT_WORKING_DIRECTORY e
# GITHUB_WORKSPACE (até onde subir procurando o lockfile).
#
# Outputs:
#   manager    bun, pnpm, yarn, npm, custom ou skip
#   command    comando de instalação (vazio com skip)
#   directory  pasta em que o comando roda (absoluta)
#   needs_bun  true quando o Bun precisa ser instalado antes
#   corepack   true quando o pnpm ou o Yarn vêm do Corepack
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_inputs
install_command="$(trim "${INPUT_INSTALL_COMMAND:-}")"
start="$(cd "$WORKING_DIRECTORY" && pwd)"

write_outputs() {
  set_output manager "$1"
  set_output command "$2"
  set_output directory "$3"
  set_output needs_bun "$4"
  set_output corepack "$5"
  if [[ -n "$2" ]]; then
    echo "Instalação: $2 (em $3)"
  fi
}

has() {
  command -v "$1" >/dev/null 2>&1
}

if [[ "$(lower "$install_command")" == "skip" ]]; then
  echo "install-command: skip. Usando as dependências já instaladas."
  write_outputs skip "" "$start" false false
  exit 0
fi

if [[ -n "$install_command" ]]; then
  needs_bun=false
  first_word="${install_command%%[[:space:]]*}"
  if [[ "$first_word" == "bun" || "$first_word" == "bunx" ]] && ! has bun; then
    needs_bun=true
  fi
  write_outputs custom "$install_command" "$start" "$needs_bun" false
  exit 0
fi

# Sobe a partir do working-directory até a raiz do repositório procurando o
# lockfile. Em monorepos ele costuma ficar na raiz.
stop="$(cd "${GITHUB_WORKSPACE:-/}" && pwd)"
dir="$start"
manager=""
while :; do
  if [[ -f "$dir/bun.lock" || -f "$dir/bun.lockb" ]]; then
    manager=bun
  elif [[ -f "$dir/pnpm-lock.yaml" ]]; then
    manager=pnpm
  elif [[ -f "$dir/yarn.lock" ]]; then
    manager=yarn
  elif [[ -f "$dir/package-lock.json" || -f "$dir/npm-shrinkwrap.json" ]]; then
    manager=npm
  fi
  [[ -z "$manager" ]] || break
  [[ "$dir" != "$stop" && "$dir" != "/" ]] || break
  dir="$(dirname "$dir")"
done

if [[ -z "$manager" ]]; then
  gh_error "Nenhum lockfile (bun.lock, pnpm-lock.yaml, yarn.lock ou package-lock.json) encontrado a partir de \"$WORKING_DIRECTORY\". Informe install-command, ou use install-command: skip se as dependências já estão instaladas."
  exit 1
fi

# Versão fixada no package.json ("packageManager": "pnpm@9.0.0"), se houver.
pinned=""
if [[ -f "$dir/package.json" ]]; then
  pinned="$(grep -oE '"packageManager"[[:space:]]*:[[:space:]]*"[a-z]+@[0-9]+' "$dir/package.json" | grep -oE '[a-z]+@[0-9]+$' || true)"
fi

needs_bun=false
corepack=false
case "$manager" in
  bun)
    install="bun install --frozen-lockfile"
    has bun || needs_bun=true
    ;;
  pnpm)
    install="pnpm install --frozen-lockfile"
    ;;
  yarn)
    # Yarn 2 ou mais novo usa --immutable; o Yarn 1 usa --frozen-lockfile.
    if [[ -f "$dir/.yarnrc.yml" || "$pinned" =~ ^yarn@([2-9]|[1-9][0-9]) ]]; then
      install="yarn install --immutable"
    else
      install="yarn install --frozen-lockfile"
    fi
    ;;
  npm)
    install="npm ci"
    ;;
esac

# pnpm e Yarn vêm do Corepack (que acompanha o Node) quando não estão no PATH
# ou quando o package.json fixa a versão.
if [[ "$manager" == "pnpm" || "$manager" == "yarn" ]]; then
  if ! has "$manager" || [[ "$pinned" == "$manager@"* ]]; then
    corepack=true
  fi
fi

write_outputs "$manager" "$install" "$dir" "$needs_bun" "$corepack"
