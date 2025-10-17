#!/usr/bin/env bash

# ------------------------------------------------------------------------------

declare -r EXPECTED_MIN_OP_CLI_VERSION="1.14.1"

# ------------------------------------------------------------------------------

op::verify_version() {
  local op_version="$(rbw --version | awk '{print $2}')"

  semver::compare "$op_version" "$EXPECTED_MIN_OP_CLI_VERSION"

  if [[ $? -eq 2 ]]; then
    tmux::display_message \
      "Bitwarden CLI version is not compatible with this plugin: ${op_version} < ${EXPECTED_MIN_OP_CLI_VERSION}"

    return 1
  fi

  return 0
}

op::get_items() {
  local -r JQ_FILTER="
  .[]
  | [(.name + \" (\" + .user + \")\"), .id]
  | join(\",\")
  "

  # Returned JSON structure reference:
  # [
  #   {
  #     "id": "UUIDV4",
  #     "name": "myitem name",
  #     "user": "av@example.com",
  #     "folder": null
  #   }
  #   ...
  # ]
  #
  #TODO(al): add folder search, via jq
  rbw ls --raw | jq "$JQ_FILTER" --raw-output
}


op::get_item_password() {
  local -r ITEM_UUID="$1"

  rbw get --field password "$ITEM_UUID"
}


op::get_item_totp() {
  # not supported by rbw.
  return ""
}
