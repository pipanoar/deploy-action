#!/usr/bin/env bash
# Testes dos scripts da action. Roda cada script como o action.yml roda, com as
# variáveis INPUT_* e um npx falso no PATH que grava os argumentos recebidos.
#
#   bash test/run.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0

# ---------------------------------------------------------------------------
# Ambiente falso

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"

# npx falso: grava uma chamada por bloco (um argumento por linha) e o token
# recebido. FAKE_NPX_FAIL=<plataforma> faz o deploy dessa plataforma falhar;
# FAKE_NPX_NO_CLI=1 simula a CLI não instalada.
cat >"$FAKE_BIN/npx" <<'EOF'
#!/usr/bin/env bash
{
  echo "--- call"
  echo "token=${PIPANOAR_TOKEN:-}"
  echo "cwd=$(pwd)"
  for arg in "$@"; do echo "arg=$arg"; done
} >>"$FAKE_NPX_LOG"
if [[ "$*" == *"--version"* ]]; then
  [[ -z "${FAKE_NPX_NO_CLI:-}" ]] || exit 1
  echo "1.0.0-rc.24"
  exit 0
fi
if [[ -n "${FAKE_NPX_FAIL:-}" && "$*" == *"-p $FAKE_NPX_FAIL"* ]]; then
  exit 3
fi
exit 0
EOF
# corepack falso, para o install.sh.
cat >"$FAKE_BIN/corepack" <<'EOF'
#!/usr/bin/env bash
echo "corepack $*" >>"$FAKE_NPX_LOG"
EOF
chmod +x "$FAKE_BIN/npx" "$FAKE_BIN/corepack"

# PATH mínimo: sem Bun, pnpm ou Yarn, para a detecção ser previsível.
BASE_PATH="$FAKE_BIN:/usr/bin:/bin"

# Projeto de exemplo com o config do preset.
new_project() {
  local dir="$WORK/projects/$1"
  mkdir -p "$dir"
  printf 'import { pipanoar } from "@pipanoar/hot-updater";\n' >"$dir/hot-updater.config.ts"
  printf '%s' "$dir"
}

# Roda um script com o ambiente limpo. Uso: run <script> [VAR=valor ...]
# Deixa em $status, $out (stdout e stderr),
# $summary ($GITHUB_STEP_SUMMARY) e $calls (log do npx falso).
run() {
  local script="$1"
  shift
  : >"$WORK/github_output"
  : >"$WORK/summary"
  : >"$WORK/npx.log"
  out="$(cd "${RUN_CWD:-$WORK}" && env -i \
    PATH="$BASE_PATH" HOME="$HOME" \
    GITHUB_OUTPUT="$WORK/github_output" \
    GITHUB_STEP_SUMMARY="$WORK/summary" \
    GITHUB_WORKSPACE="${RUN_WORKSPACE:-$WORK}" \
    FAKE_NPX_LOG="$WORK/npx.log" \
    "$@" bash "$SCRIPTS/$script" 2>&1)"
  status=$?
  summary="$(cat "$WORK/summary")"
  calls="$(cat "$WORK/npx.log")"
}

# Valor de um output gravado no formato nome<<DELIM.
output() {
  awk -v name="$1" '
    $0 ~ "^" name "<<" { delim = substr($0, length(name) + 3); reading = 1; next }
    reading && $0 == delim { reading = 0; next }
    reading { print }
  ' "$WORK/github_output"
}

# Chamadas "npx --no hot-updater deploy ...", uma por linha, a partir de "deploy".
deploy_calls() {
  awk '
    /^--- call/ { if (line != "") print line; line = ""; next }
    /^arg=/ { line = line (line == "" ? "" : " ") substr($0, 5) }
    END { if (line != "") print line }
  ' "$WORK/npx.log" | sed -n 's/^--no hot-updater deploy /deploy /p'
}

# ---------------------------------------------------------------------------
# Asserções

current=""
test_case() {
  current="$1"
}

ok() {
  passed=$((passed + 1))
}

ko() {
  failed=$((failed + 1))
  echo "FALHOU: $current: $1"
  echo "  status: $status"
  while IFS= read -r line; do echo "  | $line"; done <<<"$out"
}

expect_status() {
  if [[ "$status" == "$1" ]]; then ok; else ko "esperava status $1"; fi
}

expect_eq() {
  if [[ "$1" == "$2" ]]; then ok; else ko "esperava [$2], veio [$1]"; fi
}

expect_contains() {
  if [[ "$1" == *"$2"* ]]; then ok; else ko "esperava conter [$2]"; fi
}

expect_not_contains() {
  if [[ "$1" != *"$2"* ]]; then ok; else ko "não esperava conter [$2]"; fi
}

PROJECT="$(new_project app)"
TOKEN="pna_teste_123"

# ---------------------------------------------------------------------------
# validate.sh

test_case "validate: padrões"
run validate.sh INPUT_TOKEN="$TOKEN" INPUT_WORKING_DIRECTORY="$PROJECT" INPUT_NODE_VERSION=22
expect_status 0
expect_contains "$out" "::add-mask::$TOKEN"
expect_eq "$(output platform)" both
expect_eq "$(output channel)" production
expect_eq "$(output rollout)" 100
expect_eq "$(output force_update)" false
expect_eq "$(output disabled)" false
expect_eq "$(output setup_node)" true

test_case "validate: máscara vem antes de qualquer outra linha"
expect_eq "$(printf '%s\n' "$out" | head -n 1)" "::add-mask::$TOKEN"

test_case "validate: normaliza maiúsculas, espaços e zeros"
run validate.sh INPUT_TOKEN=" $TOKEN " INPUT_PLATFORM=" iOS " INPUT_ROLLOUT="010" \
  INPUT_FORCE_UPDATE=TRUE INPUT_DISABLED=" False" INPUT_SETUP_NODE=false INPUT_WORKING_DIRECTORY="$PROJECT"
expect_status 0
expect_eq "$(output platform)" ios
expect_eq "$(output rollout)" 10
expect_eq "$(output force_update)" true
expect_eq "$(output disabled)" false
expect_eq "$(output setup_node)" false

test_case "validate: token vazio"
run validate.sh INPUT_TOKEN="  " INPUT_WORKING_DIRECTORY="$PROJECT" INPUT_NODE_VERSION=22
expect_status 1
expect_contains "$out" "::error title=Pipa no Ar::O input token é obrigatório"
expect_not_contains "$out" "::add-mask::"

test_case "validate: platform inválido"
run validate.sh INPUT_TOKEN="$TOKEN" INPUT_PLATFORM=web INPUT_WORKING_DIRECTORY="$PROJECT" INPUT_NODE_VERSION=22
expect_status 1
expect_contains "$out" 'platform inválido: "web". Use ios, android ou both.'

for rollout in 101 -5 abc 10.5 1000; do
  test_case "validate: rollout $rollout"
  run validate.sh INPUT_TOKEN="$TOKEN" INPUT_ROLLOUT="$rollout" INPUT_WORKING_DIRECTORY="$PROJECT" INPUT_NODE_VERSION=22
  expect_status 1
  expect_contains "$out" "Use um número inteiro de 0 a 100."
done

test_case "validate: rollout 0 passa com aviso"
run validate.sh INPUT_TOKEN="$TOKEN" INPUT_ROLLOUT=0 INPUT_WORKING_DIRECTORY="$PROJECT" INPUT_NODE_VERSION=22
expect_status 0
expect_contains "$out" "::warning title=Pipa no Ar::rollout 0"
expect_eq "$(output rollout)" 0

test_case "validate: canal com espaço"
run validate.sh INPUT_TOKEN="$TOKEN" INPUT_CHANNEL="meu canal" INPUT_WORKING_DIRECTORY="$PROJECT" INPUT_NODE_VERSION=22
expect_status 1
expect_contains "$out" "O nome do canal não pode ter espaços."

test_case "validate: booleanos inválidos"
run validate.sh INPUT_TOKEN="$TOKEN" INPUT_FORCE_UPDATE=sim INPUT_DISABLED=1 INPUT_SETUP_NODE=talvez \
  INPUT_WORKING_DIRECTORY="$PROJECT" INPUT_NODE_VERSION=22
expect_status 1
expect_contains "$out" 'force-update inválido: "sim". Use true ou false.'
expect_contains "$out" 'disabled inválido: "1". Use true ou false.'
expect_contains "$out" 'setup-node inválido: "talvez". Use true ou false.'

test_case "validate: node-version vazio com setup-node"
run validate.sh INPUT_TOKEN="$TOKEN" INPUT_NODE_VERSION="" INPUT_WORKING_DIRECTORY="$PROJECT"
expect_status 1
expect_contains "$out" "node-version vazio"

test_case "validate: working-directory inexistente"
run validate.sh INPUT_TOKEN="$TOKEN" INPUT_WORKING_DIRECTORY="$WORK/nao-existe" INPUT_NODE_VERSION=22
expect_status 1
expect_contains "$out" "working-directory não encontrado"

test_case "validate: pasta sem hot-updater.config"
mkdir -p "$WORK/projects/vazio"
run validate.sh INPUT_TOKEN="$TOKEN" INPUT_WORKING_DIRECTORY="$WORK/projects/vazio" INPUT_NODE_VERSION=22
expect_status 1
expect_contains "$out" "Nenhum hot-updater.config.ts"

test_case "validate: config sem o preset gera aviso"
OTHER="$WORK/projects/outro"
mkdir -p "$OTHER"
printf 'export default {};\n' >"$OTHER/hot-updater.config.js"
run validate.sh INPUT_TOKEN="$TOKEN" INPUT_WORKING_DIRECTORY="$OTHER" INPUT_NODE_VERSION=22
expect_status 0
expect_contains "$out" "não parece usar o preset @pipanoar/hot-updater"

test_case "validate: vários erros de uma vez, sem injeção de comando"
run validate.sh INPUT_TOKEN="" INPUT_PLATFORM=$'x\n::warning::injetado' INPUT_ROLLOUT=200 INPUT_WORKING_DIRECTORY="$PROJECT" INPUT_NODE_VERSION=22
expect_status 1
expect_eq "$(grep -c '^::error' <<<"$out")" 3
expect_not_contains "$out" $'\n::warning::injetado'
expect_contains "$out" "%0A::warning::injetado"

# ---------------------------------------------------------------------------
# deploy.sh

test_case "deploy: padrões publicam iOS e depois Android"
run deploy.sh PIPANOAR_TOKEN="$TOKEN" INPUT_WORKING_DIRECTORY="$PROJECT"
expect_status 0
expect_eq "$(deploy_calls)" "deploy -p ios -c production -r 100
deploy -p android -c production -r 100"
expect_contains "$calls" "arg=--no"
expect_contains "$calls" "token=$TOKEN"
expect_contains "$calls" "cwd=$PROJECT"
expect_contains "$summary" "| iOS | production | 100% | automática | publicado |"
expect_contains "$summary" "| Android | production | 100% | automática | publicado |"
expect_contains "$summary" "https://app.pipanoar.scuderiatech.com.br"

test_case "deploy: uma plataforma"
run deploy.sh PIPANOAR_TOKEN="$TOKEN" INPUT_PLATFORM=android INPUT_WORKING_DIRECTORY="$PROJECT"
expect_status 0
expect_eq "$(deploy_calls)" "deploy -p android -c production -r 100"
expect_not_contains "$summary" "iOS"

test_case "deploy: canal, rollout, versão alvo, mensagem, force e disabled"
run deploy.sh PIPANOAR_TOKEN="$TOKEN" INPUT_PLATFORM=ios INPUT_CHANNEL=beta INPUT_ROLLOUT=10 \
  INPUT_TARGET_APP_VERSION="1.4.x" INPUT_MESSAGE="Corrige o login (#42)" \
  INPUT_FORCE_UPDATE=true INPUT_DISABLED=true INPUT_WORKING_DIRECTORY="$PROJECT"
expect_status 0
expect_eq "$(deploy_calls)" "deploy -p ios -c beta -r 10 -t 1.4.x -m Corrige o login (#42) -f -d"
expect_contains "$calls" "arg=Corrige o login (#42)"
expect_contains "$summary" "| iOS | beta | 10% | 1.4.x | publicado |"
expect_contains "$summary" "Atualização forçada"
expect_contains "$summary" "Release criada desativada"

test_case "deploy: mensagem com várias linhas e aspas vai como um argumento"
run deploy.sh PIPANOAR_TOKEN="$TOKEN" INPUT_PLATFORM=ios INPUT_MESSAGE=$'Título "x"\n\ncorpo $HOME' INPUT_WORKING_DIRECTORY="$PROJECT"
expect_status 0
expect_contains "$calls" $'arg=Título "x"\n\ncorpo $HOME'

test_case "deploy: falha no iOS para antes do Android"
run deploy.sh PIPANOAR_TOKEN="$TOKEN" FAKE_NPX_FAIL=ios INPUT_WORKING_DIRECTORY="$PROJECT"
expect_status 3
expect_eq "$(deploy_calls)" "deploy -p ios -c production -r 100"
expect_contains "$out" "O deploy de iOS falhou (código 3)"
expect_contains "$summary" "| iOS | production | 100% | automática | falhou |"
expect_contains "$summary" "| Android | production | 100% | automática | não executado |"

test_case "deploy: CLI não instalada"
run deploy.sh PIPANOAR_TOKEN="$TOKEN" FAKE_NPX_NO_CLI=1 INPUT_WORKING_DIRECTORY="$PROJECT"
expect_status 1
expect_contains "$out" "A CLI do hot-updater não está instalada"
expect_eq "$(deploy_calls)" ""

test_case "deploy: sem token"
run deploy.sh INPUT_WORKING_DIRECTORY="$PROJECT"
expect_status 1
expect_contains "$out" "Token de deploy vazio"
expect_eq "$calls" ""

test_case "deploy: o token não aparece no log"
run deploy.sh PIPANOAR_TOKEN="$TOKEN" INPUT_WORKING_DIRECTORY="$PROJECT"
expect_not_contains "$out" "$TOKEN"
expect_not_contains "$summary" "$TOKEN"

# ---------------------------------------------------------------------------
# detect.sh e install.sh

detect_in() {
  RUN_WORKSPACE="$1" run detect.sh INPUT_WORKING_DIRECTORY="$2" "${@:3}"
}

for case_ in "bun.lock:bun:bun install --frozen-lockfile" \
  "bun.lockb:bun:bun install --frozen-lockfile" \
  "pnpm-lock.yaml:pnpm:pnpm install --frozen-lockfile" \
  "yarn.lock:yarn:yarn install --frozen-lockfile" \
  "package-lock.json:npm:npm ci"; do
  lockfile="${case_%%:*}"
  rest="${case_#*:}"
  test_case "detect: $lockfile"
  dir="$WORK/detect/$lockfile"
  mkdir -p "$dir"
  touch "$dir/$lockfile"
  detect_in "$dir" "$dir"
  expect_status 0
  expect_eq "$(output manager)" "${rest%%:*}"
  expect_eq "$(output command)" "${rest#*:}"
  expect_eq "$(output directory)" "$dir"
done

if PATH="/usr/bin:/bin" command -v bun >/dev/null 2>&1; then
  echo "(bun está em /usr/bin; pulando o teste de needs_bun)"
else
  test_case "detect: Bun ausente pede setup-bun"
  detect_in "$WORK/detect/bun.lock" "$WORK/detect/bun.lock"
  expect_eq "$(output needs_bun)" true
fi

if PATH="/usr/bin:/bin" command -v pnpm >/dev/null 2>&1; then
  echo "(pnpm está em /usr/bin; pulando o teste de Corepack)"
else
  test_case "detect: pnpm ausente usa Corepack"
  detect_in "$WORK/detect/pnpm-lock.yaml" "$WORK/detect/pnpm-lock.yaml"
  expect_eq "$(output corepack)" true
fi

test_case "detect: Yarn moderno usa --immutable"
dir="$WORK/detect/yarn-berry"
mkdir -p "$dir"
touch "$dir/yarn.lock"
printf '{ "packageManager": "yarn@4.5.0" }\n' >"$dir/package.json"
detect_in "$dir" "$dir"
expect_eq "$(output command)" "yarn install --immutable"
expect_eq "$(output corepack)" true

test_case "detect: monorepo acha o lockfile na raiz"
mono="$WORK/detect/mono"
mkdir -p "$mono/apps/mobile"
touch "$mono/pnpm-lock.yaml"
detect_in "$mono" "$mono/apps/mobile"
expect_eq "$(output manager)" pnpm
expect_eq "$(output directory)" "$mono"

test_case "detect: não sobe além do workspace"
mkdir -p "$mono/apps/mobile/sub"
detect_in "$mono/apps/mobile" "$mono/apps/mobile/sub"
expect_status 1
expect_contains "$out" "Nenhum lockfile"

test_case "detect: install-command explícito"
detect_in "$mono" "$mono/apps/mobile" INPUT_INSTALL_COMMAND="npm install --legacy-peer-deps"
expect_status 0
expect_eq "$(output manager)" custom
expect_eq "$(output command)" "npm install --legacy-peer-deps"
expect_eq "$(output directory)" "$mono/apps/mobile"

test_case "detect: install-command skip"
detect_in "$mono" "$mono/apps/mobile" INPUT_INSTALL_COMMAND=SKIP
expect_status 0
expect_eq "$(output manager)" skip
expect_eq "$(output command)" ""

test_case "install: roda o comando na pasta, com Corepack"
inst="$WORK/install"
mkdir -p "$inst"
run install.sh INSTALL_COMMAND='pwd > installed.txt' INSTALL_DIRECTORY="$inst" INSTALL_COREPACK=true
expect_status 0
expect_eq "$(cat "$inst/installed.txt")" "$inst"
expect_contains "$calls" "corepack enable"

test_case "install: falha do comando falha o step"
run install.sh INSTALL_COMMAND='exit 7' INSTALL_DIRECTORY="$inst"
expect_status 7

test_case "install: sem comando não faz nada"
run install.sh INSTALL_COMMAND=""
expect_status 0
expect_contains "$out" "Nada para instalar."

# ---------------------------------------------------------------------------

echo
echo "$passed verificações passaram, $failed falharam."
((failed == 0))
