#!/usr/bin/env bash

# ------------------------------------------------------------------------------

declare -r EXPECTED_MIN_OP_CLI_VERSION="2025.9.0"
declare -r TMP_TOKEN_FILE="$HOME/.op_tmux_token_tmp"

# ------------------------------------------------------------------------------

op::verify_version() {
  local op_version="$(bw --version)"

  semver::compare "$op_version" "$EXPECTED_MIN_OP_CLI_VERSION"

  if [[ $? -eq 2 ]]; then
    tmux::display_message \
      "Bitwarden CLI version is not compatible with this plugin: ${op_version} < ${EXPECTED_MIN_OP_CLI_VERSION}"

    return 1
  fi

  return 0
}

op::verify_logged_from_raw() {
  local test_query="$1"

  if [[ $test_query == *"Master Password is required"* ]]; then
    return 1
  fi
}


op::unlock() {
  local password=""

  echo "Bitwarden vault needs to be unlocked."
  printf "\\e[0;33m[?]\\e[0m Master Password: "
  read -r -s password
  echo -ne "\n"

  local unlock_out="$(echo "$password" | bw unlock 2>&1)"

  if [[ $unlock_out == *"Invalid master password"* ]]; then
    echo "Invalid master password."
    return 1
  fi

  # Extract the temporary auth token from the bitwarden cli stdout.
  # The token is usually in the text ... BW_SESSION="<TOKEN>" ...
  local tmp_token="$(echo "$unlock_out" | grep -m 1 -oP 'BW_SESSION="\K[^"]*')"

  if [ ${#tmp_token} -lt 10 ]; then
    echo "Could not parse bitwarden output."
    return 1
  fi

  op::store_session "$tmp_token"

  exit_code=$?

  tput clear

  return $exit_code
}


op::store_session() {
  local tmp_token="$1"
  echo "$tmp_token" > "$TMP_TOKEN_FILE"
}

op::get_session() {
  local token="$(cat "$TMP_TOKEN_FILE" 2> /dev/null )"

  if [ ${#token} -lt 10 ]; then
    echo "token_error"
  else
    echo "$token"
  fi
}

op::parse_items_from_raw() {
  local items_raw="$1"
  # Returned JSON structure reference:
  # [
  # {
  #   "passwordHistory": [],
  #   "revisionDate": "2025-06-17T09:27:44.514Z",
  #   "creationDate": "2025-06-17T09:26:29.696Z",
  #   "deletedDate": null,
  #   "object": "item",
  #   "id": "5071a732-6457-4235-a4f0-c0171664a329",
  #   "organizationId": null,
  #   "folderId": null,
  #   "type": 1,
  #   "reprompt": 0,
  #   "name": "example.com name1",
  #   "notes": null,
  #   "favorite": false,
  #   "fields": [],
  #   "login": {
  #     "uris": [
  #       {
  #         "match": null,
  #         "uri": "https://example.com"
  #       }
  #     ],
  #     "username": "admin@example.com",
  #     "password": "password",
  #     "totp": null,
  #     "passwordRevisionDate": null
  #   },
  #   "collectionIds": [],
  #   "attachments": []
  # },
  #  ...
  # ]

  local -r JQ_FILTER="
  .[]
  | select(.object == \"item\")
  | [(.name + \" (\" + .login.username + \")\"), .id]
  | join(\",\")
  "
  # bitwarden: if empty, folderid filter is ignored
  echo "$items_raw" | jq "$JQ_FILTER" --raw-output

}


op::get_items_raw() {
  # returns either the text for a login prompt,
  # or a json with all password items.
  echo "" | bw list items \
    --folderid "$(options::op_filter_tags)" \
    --session "$(op::get_session)" \
    2>&1
}

op::get_item_password() {
  local -r ITEM_UUID="$1"

  bw get password "$ITEM_UUID" \
    --session "$(op::get_session)" \
    2> /dev/null
}

op::get_item_totp() {
  local -r ITEM_UUID="$1"

  bw get totp "$ITEM_UUID" \
    --session "$(op::get_session)" \
    2> /dev/null
}
