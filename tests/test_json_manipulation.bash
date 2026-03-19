#!/bin/bash

# Get directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/test_helper.bash"

test_start "JSON Manipulation Logic"

# Setup a temporary JSON file for testing
TEST_JSON=$(mktemp)
cat > "$TEST_JSON" << 'EOF'
{
  "inbounds": [
    {
      "port": 8443,
      "settings": {
        "clients": [
          {
            "id": "test-uuid-1234"
          }
        ]
      },
      "streamSettings": {
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": [
            "www.microsoft.com"
          ],
          "shortIds": [
            "test-short-id"
          ]
        }
      }
    }
  ]
}
EOF

# Test 1: Extract UUID
uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$TEST_JSON")
assert_equals "test-uuid-1234" "$uuid" "Extract UUID using jq"

# Test 2: Extract Port
port=$(jq -r '.inbounds[0].port // empty' "$TEST_JSON")
assert_equals "8443" "$port" "Extract Port using jq"

# Test 3: Extract ServerName
server_name=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$TEST_JSON")
assert_equals "www.microsoft.com" "$server_name" "Extract ServerName from array using jq"

# Test 4: Extract ShortId
short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$TEST_JSON")
assert_equals "test-short-id" "$short_id" "Extract ShortId from array using jq"

# Test 5: Handle missing key with empty
missing=$(jq -r '.inbounds[0].missingKey // empty' "$TEST_JSON")
assert_equals "" "$missing" "Handle missing key by returning empty string"

# Test 6: Update JSON value
new_short_id="new-short-id-5678"
jq --arg sid "$new_short_id" '.inbounds[0].streamSettings.realitySettings.shortIds[0] = $sid' "$TEST_JSON" > "${TEST_JSON}.tmp" && mv "${TEST_JSON}.tmp" "$TEST_JSON"
updated_short_id=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$TEST_JSON")
assert_equals "$new_short_id" "$updated_short_id" "Update ShortId in JSON using jq"

# Cleanup
rm -f "$TEST_JSON"

test_end
