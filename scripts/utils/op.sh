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

op::verify_session() {
  # To determine if we need to unlock the vault, we perform a query for
  # an item that does't exist, and check the stout for password prompts
  local test_query="$(echo "" | bw get item tmux-bw-probe --session $(op::get_session) 2>&1)"
  local password=""

  if [[ $test_query == *"Master Password is required"* ]]; then

    echo "Bitwarden vault needs to be unlocked."
    printf "\\e[0;33m[?]\\e[0m Master Password: "
    read -r -s password
    echo -ne "\n"

    if ! op::unlock "$password"; then
      return 1
    fi
  fi

}

op::unlock() {
  local password="$1"
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
  cat "$TMP_TOKEN_FILE" 2> /dev/null
}

op::get_all_items() {

  # Returned JSON structure reference:
  # https://developer.1password.com/docs/cli/item-template-json

  local -r JQ_FILTER="
    .[]
    | [
        select(
          (.category == \"LOGIN\") or
          (.category == \"PASSWORD\")
        )?
      ]
    | map(
        [ .title, .id ]
        | join(\",\")
      )
    | .[]
  "

  op item list \
    --cache \
    --format json \
    --categories="LOGIN,PASSWORD" \
    --tags="$(options::op_filter_tags)" \
    --vault="$(options::op_valut)" \
    --session="$(op::get_session)" \
    2> /dev/null \
    | jq "$JQ_FILTER" --raw-output
}

op::get_item_password() {
  local -r ITEM_UUID="$1"

  # Returned JSON structure reference:
  # https://developer.1password.com/docs/cli/item-template-json
  #
  # In case there are multiple items, we'll take the first one that matches our criteria.

  local -r JQ_FILTER="
      # For cases where we might get a single item - we always want to start with an array
      [.] + [] | flatten

      # Select the items whose purpose is... being a password
      | map(select(.purpose == \"PASSWORD\"))

      # Select the first one
      | .[0]

      # Return the value
      | .value
    "

  op item get "$ITEM_UUID" \
    --cache \
    --fields type=concealed \
    --format json \
    --session="$(op::get_session)" \
    | jq "$JQ_FILTER" --raw-output
}

op::get_item_totp() {
  local -r ITEM_UUID="$1"

  # In this case, the structure looks very similar to the password section, but the type of "OTP".

  local -r JQ_FILTER="
      # For cases where we might get a single item - we always want to start with an array
      [.] + [] | flatten

      # Select the first one
      | .[0]

      # Return the value
      | .totp
    "

  op item get "$ITEM_UUID" \
    --cache \
    --fields type=otp \
    --format json \
    --session="$(op::get_session)" \
    | jq "$JQ_FILTER" --raw-output
}
