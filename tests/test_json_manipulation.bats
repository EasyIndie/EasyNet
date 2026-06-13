#!/usr/bin/env bats

load test_helper

setup_file() {
    # Create a temp JSON fixture shared across tests
    export TEST_JSON=$(mktemp /tmp/easynet-test-json.XXXXXX)
    cat > "$TEST_JSON" << 'EOF'
{
  "inbounds": [
    {
      "port": 8443,
      "settings": {
        "clients": [
          { "id": "test-uuid-1234" }
        ]
      },
      "streamSettings": {
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": [ "www.microsoft.com" ],
          "shortIds": [ "test-short-id" ]
        }
      }
    }
  ]
}
EOF
}

teardown_file() {
    rm -f "$TEST_JSON"
}

@test "Extract UUID using jq" {
    uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$TEST_JSON")
    [ "$uuid" = "test-uuid-1234" ]
}

@test "Extract Port using jq" {
    port=$(jq -r '.inbounds[0].port // empty' "$TEST_JSON")
    [ "$port" = "8443" ]
}

@test "Extract ServerName from array using jq" {
    server_name=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$TEST_JSON")
    [ "$server_name" = "www.microsoft.com" ]
}

@test "Extract ShortId from array using jq" {
    short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$TEST_JSON")
    [ "$short_id" = "test-short-id" ]
}

@test "Handle missing key by returning empty string" {
    missing=$(jq -r '.inbounds[0].missingKey // empty' "$TEST_JSON")
    [ -z "$missing" ]
}

@test "Update ShortId in JSON using jq" {
    new_short_id="new-short-id-5678"
    jq --arg sid "$new_short_id" '.inbounds[0].streamSettings.realitySettings.shortIds[0] = $sid' "$TEST_JSON" > "${TEST_JSON}.tmp"
    mv "${TEST_JSON}.tmp" "$TEST_JSON"
    updated_short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$TEST_JSON")
    [ "$updated_short_id" = "$new_short_id" ]
}
