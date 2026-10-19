#!/usr/bin/env bash
# Tests source selected helper sections dynamically and isolate environment changes in subshells.
# shellcheck disable=SC1090,SC2030,SC2031
set -euo pipefail

helper="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gh-git-user-credential"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
test_path="$test_dir/path"
mkdir -p "$test_path"
ln -s "$(builtin command -v sed)" "$test_path/sed"

command() {
  if [[ "${1:-}" == -v && "${2:-}" == gh ]]; then
    return 1
  fi
  builtin command "$@"
}

cygpath() {
  case "$2" in
    C:/*) printf '%s/%s\n' "$test_dir" "${2#C:/}" ;;
    *) printf '%s\n' "$2" ;;
  esac
}

check_windows_path() (
  expected="$test_dir/$1"
  shift
  GH_BIN=
  unset PROGRAMFILES ProgramFiles ProgramW6432 LOCALAPPDATA ChocolateyInstall SCOOP
  export OSTYPE=msys HOME="$test_dir/home"
  if [[ "$#" -gt 0 ]]; then
    export "${@?}"
  fi
  mkdir -p "$(dirname "$expected")"
  ln -s /usr/bin/true "$expected"
  source <(sed '/^GIT_USER=/,$d' "$helper")
  [[ "$GH_BIN" == "$expected" ]]
  printf 'PASS: %s\n' "$expected"
)

check_windows_path 'Program Files/GitHub CLI/gh.exe' 'PROGRAMFILES=C:/Program Files'
check_windows_path 'Program Files Alt/GitHub CLI/gh.exe' 'ProgramFiles=C:/Program Files Alt'
check_windows_path 'Program Files 64/GitHub CLI/gh.exe' 'ProgramW6432=C:/Program Files 64'
check_windows_path 'Local Apps/Microsoft/WinGet/Links/gh.exe' 'LOCALAPPDATA=C:/Local Apps'
check_windows_path 'Chocolatey/bin/gh.exe' 'ChocolateyInstall=C:/Chocolatey'
check_windows_path 'Scoop/apps/gh/current/bin/gh.exe' 'SCOOP=C:/Scoop'
check_windows_path 'home/scoop/apps/gh/current/bin/gh.exe'

(
  export OSTYPE=cygwin GH_BIN='C:/Program Files/GitHub CLI/gh.exe'
  source <(sed '/^GIT_USER=/,$d' "$helper")
  [[ "$GH_BIN" == "$test_dir/Program Files/GitHub CLI/gh.exe" ]]
  printf 'PASS: explicit Windows path conversion\n'
)

for platform in linux-gnu darwin freebsd; do
  (
    GH_BIN=
    export OSTYPE="$platform" HOME="$test_dir/home"
    mkdir -p "$HOME/.local/bin"
    ln -sf /usr/bin/true "$HOME/.local/bin/gh"
    export PATH="$test_path"
    source <(sed '/^GIT_USER=/,$d' "$helper")
    [[ -x "$GH_BIN" ]]
    # shellcheck disable=SC2154
    [[ " ${candidates[*]} " == *" $HOME/.local/bin/gh "* ]]
    if [[ "$platform" != darwin ]]; then
      [[ " ${candidates[*]} " == *' /snap/bin/gh '* ]]
      [[ " ${candidates[*]} " == *' /home/linuxbrew/.linuxbrew/bin/gh '* ]]
    fi
    printf 'PASS: %s fallback candidates\n' "$platform"
  )
  (
    export OSTYPE="$platform" GH_BIN=/usr/bin/true
    source <(sed '/^GIT_USER=/,$d' "$helper")
    [[ "$GH_BIN" == /usr/bin/true ]]
    printf 'PASS: %s explicit path priority\n' "$platform"
  )
done

check_credentials() (
  export GH_HOST="$1" GH_BIN=mock_gh
  github_status="$2"
  enterprise_status="$3"
  export GH_TOKEN=existing-github GH_ENTERPRISE_TOKEN=existing-enterprise
  expected_github=existing-github
  expected_enterprise=existing-enterprise
  expected_calls=2
  if [[ "$github_status" -eq 0 ]]; then
    expected_github=new-github
  fi
  if [[ "$GH_HOST" != github.com ]]; then
    expected_calls=3
    if [[ "$enterprise_status" -eq 0 ]]; then
      expected_enterprise=new-enterprise
    fi
  fi
  : > "$test_dir/calls"
  # shellcheck disable=SC2329
  git() {
    [[ "$*" == 'config user.name' ]]
    printf '%s\n' test-user
  }
  # shellcheck disable=SC2329
  mock_gh() {
    printf '%s\n' "$*" >> "$test_dir/calls"
    if [[ "$2" == token ]]; then
      if [[ "$3" == -h ]]; then
        [[ "$*" == 'auth token -h github.com -u test-user' ]] || return 2
        printf '%s\n' new-github
        return "$github_status"
      fi
      [[ "$*" == 'auth token -u test-user' ]] || return 2
      printf '%s\n' new-enterprise
      return "$enterprise_status"
    fi
    [[ "$1" == auth && "$2" == git-credential && "$#" -eq 4 ]]
    [[ "$3" == get && "$4" == 'argument with spaces' ]]
    [[ "$(printenv GH_TOKEN)" == "$expected_github" ]]
    [[ "$(printenv GH_ENTERPRISE_TOKEN)" == "$expected_enterprise" ]]
  }
  source <(sed -n '/^GIT_USER=/,$p' "$helper") get 'argument with spaces'
  [[ "$(wc -l < "$test_dir/calls")" -eq "$expected_calls" ]]
  printf 'PASS: %s token retrieval (GitHub=%s, Enterprise=%s)\n' \
    "$GH_HOST" "$github_status" "$enterprise_status"
)

check_credentials github.com 0 0
check_credentials github.com 1 1
check_credentials github.example.com 0 0
check_credentials github.example.com 1 0
check_credentials github.example.com 0 1
check_credentials github.example.com 1 1
check_credentials '' 0 0
