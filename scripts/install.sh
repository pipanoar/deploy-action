#!/usr/bin/env bash
# Instala as dependências do projeto com o comando escolhido pelo detect.sh.
# Este step não recebe o token de deploy.
#
# Variáveis lidas: INSTALL_COMMAND, INSTALL_DIRECTORY, INSTALL_COREPACK.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

install_command="${INSTALL_COMMAND:-}"
directory="${INSTALL_DIRECTORY:-.}"

if [[ -z "$install_command" ]]; then
  echo "Nada para instalar."
  exit 0
fi

if [[ "${INSTALL_COREPACK:-false}" == "true" ]]; then
  if command -v corepack >/dev/null 2>&1; then
    # Sem a pergunta "Corepack is about to download...", que travaria o CI.
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    echo "+ corepack enable"
    corepack enable
  else
    gh_warning "O Corepack não está disponível. Instale o pnpm ou o Yarn antes da action, ou use setup-node: true."
  fi
fi

cd "$directory"
echo "+ $install_command"
bash -c "$install_command"
