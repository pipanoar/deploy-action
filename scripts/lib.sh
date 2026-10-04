# shellcheck shell=bash
# Funções comuns aos scripts da action. Carregado com `source`.

# Tira espaços e quebras de linha das pontas.
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Escapa um texto para comandos de workflow (::error::, ::warning::).
# Sem isso, uma quebra de linha num input viraria um comando novo no log.
escape_command() {
  local value="$1"
  value="${value//'%'/%25}"
  value="${value//$'\r'/%0D}"
  value="${value//$'\n'/%0A}"
  printf '%s' "$value"
}

gh_error() {
  printf '::error title=Pipa no Ar::%s\n' "$(escape_command "$1")"
}

gh_warning() {
  printf '::warning title=Pipa no Ar::%s\n' "$(escape_command "$1")"
}

gh_notice() {
  printf '::notice title=Pipa no Ar::%s\n' "$(escape_command "$1")"
}

# Grava um output do step. Usa o formato com delimitador, que aceita qualquer valor.
set_output() {
  local name="$1" value="$2"
  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  local delimiter="PIPANOAR_${RANDOM}${RANDOM}"
  {
    printf '%s<<%s\n' "$name" "$delimiter"
    printf '%s\n' "$value"
    printf '%s\n' "$delimiter"
  } >>"$GITHUB_OUTPUT"
}

# Normaliza um booleano ("True", " false ") para true/false. Vazio vira o padrão.
# Devolve o valor original quando não é booleano, para a validação acusar.
normalize_bool() {
  local value
  value="$(lower "$(trim "$1")")"
  [[ -n "$value" ]] || value="$2"
  printf '%s' "$value"
}

# Valores dos inputs já normalizados, com os padrões da action.
# Os scripts leem as variáveis INPUT_* (as mesmas que o action.yml passa).
# shellcheck disable=SC2034 # as variáveis são usadas por quem carrega o lib.sh
load_inputs() {
  PLATFORM="$(lower "$(trim "${INPUT_PLATFORM:-}")")"
  [[ -n "$PLATFORM" ]] || PLATFORM="both"

  CHANNEL="$(trim "${INPUT_CHANNEL:-}")"
  [[ -n "$CHANNEL" ]] || CHANNEL="production"

  ROLLOUT="$(trim "${INPUT_ROLLOUT:-}")"
  [[ -n "$ROLLOUT" ]] || ROLLOUT="100"
  # "010" vira "10"; o que não é número fica como está para a validação.
  if [[ "$ROLLOUT" =~ ^[0-9]+$ ]]; then
    ROLLOUT="${ROLLOUT#"${ROLLOUT%%[!0]*}"}"
    [[ -n "$ROLLOUT" ]] || ROLLOUT="0"
  fi

  TARGET_APP_VERSION="$(trim "${INPUT_TARGET_APP_VERSION:-}")"
  MESSAGE="$(trim "${INPUT_MESSAGE:-}")"
  FORCE_UPDATE="$(normalize_bool "${INPUT_FORCE_UPDATE:-}" false)"
  DISABLED="$(normalize_bool "${INPUT_DISABLED:-}" false)"
  SETUP_NODE="$(normalize_bool "${INPUT_SETUP_NODE:-}" true)"
  NODE_VERSION="$(trim "${INPUT_NODE_VERSION:-}")"

  WORKING_DIRECTORY="$(trim "${INPUT_WORKING_DIRECTORY:-}")"
  [[ -n "$WORKING_DIRECTORY" ]] || WORKING_DIRECTORY="."
}

# Lista de plataformas na ordem do deploy.
platforms_for() {
  case "$1" in
    both) printf '%s\n' ios android ;;
    *) printf '%s\n' "$1" ;;
  esac
}

platform_label() {
  case "$1" in
    ios) printf 'iOS' ;;
    android) printf 'Android' ;;
    *) printf '%s' "$1" ;;
  esac
}
