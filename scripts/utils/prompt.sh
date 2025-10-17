#!/usr/bin/env bash

# ------------------------------------------------------------------------------

prompt::ask() {
  local question="$1"

  printf "\\e[0;33m[?]\\e[0m %b [y/N] " "$question"
  read -r -n 1
  echo -ne "\n"
}

prompt::answer_is_yes() {
  [[ "$REPLY" =~ ^[Yy]$ ]] \
    && return 0 \
    || return 1
}

prompt::password() {
  local prompt_message="${1:-Master Password}"
  local password=""

  printf "\\e[0;33m[?]\\e[0m %b: " "$prompt_message"
  read -r -s password
  echo -ne "\n"

  echo "$password"
}
