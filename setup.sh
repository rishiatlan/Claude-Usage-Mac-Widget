#!/bin/bash

# setup.sh — Interactive credential setup for Claude Usage Mac Widget
#
# SECURITY NOTE:
# This script does NOT access your browser, cookies, Keychain, or any local files.
# You manually paste your session key. The script only contacts claude.ai/api to
# fetch your org ID and validate credentials. Input is masked (not shown on screen).
# Credentials are saved locally to macOS UserDefaults — never logged or transmitted
# anywhere except claude.ai.

APP_DOMAIN="com.claude.usage"
SESSION_KEY_PREF="claudeSessionKey"
ORG_ID_PREF="claudeOrganizationId"
API_BASE="https://claude.ai/api"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

print_ok()   { echo -e "${GREEN}✓${RESET} $1"; }
print_err()  { echo -e "${RED}✗${RESET} $1"; }
print_warn() { echo -e "${YELLOW}⚠${RESET} $1"; }
print_step() { echo -e "\n${BLUE}${BOLD}[$1]${RESET} $2"; }

# --- Banner ---
echo ""
echo -e "${BOLD}Claude Usage Widget — Setup${RESET}"
echo -e "${DIM}Configures your credentials so the widget can fetch usage data.${RESET}"
echo ""

# --- Check for existing credentials ---
EXISTING_KEY=$(defaults read "$APP_DOMAIN" "$SESSION_KEY_PREF" 2>/dev/null)
EXISTING_ORG=$(defaults read "$APP_DOMAIN" "$ORG_ID_PREF" 2>/dev/null)

if [ -n "$EXISTING_KEY" ] && [ -n "$EXISTING_ORG" ]; then
    MASKED_KEY="${EXISTING_KEY:0:12}...${EXISTING_KEY: -8}"
    echo -e "Existing credentials found:"
    echo -e "  Session key: ${DIM}${MASKED_KEY}${RESET}"
    echo -e "  Org ID:      ${DIM}${EXISTING_ORG}${RESET}"
    echo ""
    read -r -p "Update credentials? [y/N] " UPDATE_CHOICE
    if [[ "$UPDATE_CHOICE" != "y" && "$UPDATE_CHOICE" != "Y" ]]; then
        echo ""
        print_ok "Keeping existing credentials. You're all set."
        exit 0
    fi
    echo ""
fi

# ============================================================
# Step 1: Session Key
# ============================================================
print_step "1/3" "Session Key"
echo ""
echo "Open claude.ai in your browser, then:"
echo ""
echo "  1. Open DevTools        →  Cmd + Option + I"
echo "  2. Go to Application tab (Chrome) or Storage tab (Safari)"
echo "  3. Expand Cookies       →  click https://claude.ai"
echo "  4. Find the row named   →  sessionKey"
echo "  5. Copy the full value  →  starts with sk-ant-sid..."
echo ""

get_session_key() {
    SESSION_KEY=""
    local ATTEMPTS=0
    local MAX_ATTEMPTS=3

    while [ -z "$SESSION_KEY" ] && [ "$ATTEMPTS" -lt "$MAX_ATTEMPTS" ]; do
        ATTEMPTS=$((ATTEMPTS + 1))

        echo -n "Paste your session key (input is hidden): "
        read -s -r RAW_KEY
        echo ""

        # Trim whitespace
        RAW_KEY=$(echo "$RAW_KEY" | xargs)

        if [ -z "$RAW_KEY" ]; then
            print_err "No input received. Try again. ($ATTEMPTS/$MAX_ATTEMPTS)"
            continue
        fi

        if [[ "$RAW_KEY" != sk-ant-sid* ]]; then
            print_err "Invalid format — session key should start with 'sk-ant-sid'. Try again. ($ATTEMPTS/$MAX_ATTEMPTS)"
            continue
        fi

        SESSION_KEY="$RAW_KEY"
        print_ok "Session key accepted (format valid)."
    done

    if [ -z "$SESSION_KEY" ]; then
        echo ""
        print_err "Too many failed attempts. Run ./setup.sh to try again."
        exit 1
    fi
}

prompt_manual_org_id() {
    echo ""
    echo "To find your org ID manually:"
    echo "  1. Open DevTools on claude.ai  →  Cmd + Option + I"
    echo "  2. Go to the Network tab"
    echo "  3. Send any message in Claude"
    echo "  4. Find a request URL containing /organizations/"
    echo "  5. Copy the UUID after /organizations/ (format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
    echo ""
    read -r -p "Paste your organization ID: " MANUAL_ORG
    MANUAL_ORG=$(echo "$MANUAL_ORG" | xargs)
    if [[ "$MANUAL_ORG" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        ORG_ID="$MANUAL_ORG"
        print_ok "Organization ID accepted."
    else
        print_err "Invalid UUID format. Run ./setup.sh to try again."
        exit 1
    fi
}

# --- Step 1: Session Key ---
get_session_key

# ============================================================
# Step 2: Organization ID (automatic)
# ============================================================
print_step "2/3" "Organization ID"
echo ""
echo -e "${DIM}Fetching your organizations from Claude API...${RESET}"

ORG_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Cookie: sessionKey=$SESSION_KEY" \
    -H "Accept: application/json" \
    "$API_BASE/organizations" 2>/dev/null)

HTTP_CODE=$(echo "$ORG_RESPONSE" | tail -1)
BODY=$(echo "$ORG_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo ""
    print_err "Session key is invalid or expired (HTTP $HTTP_CODE)."
    echo ""
    echo "This usually means the key you pasted has already expired."
    echo "Go back to claude.ai → DevTools → Cookies → copy a fresh sessionKey."
    echo ""
    read -r -p "Try again with a new key? [Y/n] " RETRY_KEY
    if [[ "$RETRY_KEY" != "n" && "$RETRY_KEY" != "N" ]]; then
        print_step "1/3" "Session Key (retry)"
        echo ""
        get_session_key

        # Retry org fetch
        echo -e "${DIM}Fetching organizations...${RESET}"
        ORG_RESPONSE=$(curl -s -w "\n%{http_code}" \
            -H "Cookie: sessionKey=$SESSION_KEY" \
            -H "Accept: application/json" \
            "$API_BASE/organizations" 2>/dev/null)
        HTTP_CODE=$(echo "$ORG_RESPONSE" | tail -1)
        BODY=$(echo "$ORG_RESPONSE" | sed '$d')

        if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
            print_err "Still getting HTTP $HTTP_CODE. The session key may not be valid."
            echo ""
            echo "You can still set up manually:"
            prompt_manual_org_id
        fi
    else
        echo ""
        print_err "Setup cancelled. Run ./setup.sh when you have a fresh session key."
        exit 1
    fi
fi

if [ -z "$ORG_ID" ] && [ "$HTTP_CODE" != "200" ]; then
    echo ""
    print_warn "Could not reach Claude API (HTTP $HTTP_CODE)."
    echo ""
    read -r -p "Enter org ID manually instead? [Y/n] " MANUAL_CHOICE
    if [[ "$MANUAL_CHOICE" != "n" && "$MANUAL_CHOICE" != "N" ]]; then
        prompt_manual_org_id
    else
        print_err "Setup cancelled. Check your network and run ./setup.sh again."
        exit 1
    fi
fi

# Parse org UUIDs and names from the JSON array
if [ -z "$ORG_ID" ]; then
    # Extract UUIDs
    ORG_IDS=($(echo "$BODY" | grep -oE '"uuid"\s*:\s*"[0-9a-f-]{36}"' | grep -oE '[0-9a-f-]{36}'))
    # Extract names (simple extraction)
    ORG_NAMES=($(echo "$BODY" | grep -oE '"name"\s*:\s*"[^"]*"' | sed 's/"name"\s*:\s*"//;s/"$//'))

    if [ ${#ORG_IDS[@]} -eq 0 ]; then
        print_warn "No organizations found in API response."
        prompt_manual_org_id
    elif [ ${#ORG_IDS[@]} -eq 1 ]; then
        ORG_ID="${ORG_IDS[0]}"
        ORG_NAME="${ORG_NAMES[0]:-unknown}"
        print_ok "Organization found: ${ORG_NAME}"
    else
        echo ""
        echo "Multiple organizations found:"
        for i in "${!ORG_IDS[@]}"; do
            NAME="${ORG_NAMES[$i]:-unnamed}"
            echo "  $((i + 1)). ${NAME}  (${ORG_IDS[$i]})"
        done
        echo ""
        read -r -p "Select organization [1-${#ORG_IDS[@]}]: " ORG_CHOICE
        ORG_INDEX=$((ORG_CHOICE - 1))
        if [ "$ORG_INDEX" -ge 0 ] && [ "$ORG_INDEX" -lt "${#ORG_IDS[@]}" ]; then
            ORG_ID="${ORG_IDS[$ORG_INDEX]}"
            print_ok "Selected: ${ORG_NAMES[$ORG_INDEX]:-unnamed}"
        else
            print_err "Invalid selection. Run ./setup.sh to try again."
            exit 1
        fi
    fi
fi

# ============================================================
# Step 3: Validate
# ============================================================
print_step "3/3" "Validating credentials"
echo ""
echo -e "${DIM}Testing API access...${RESET}"

USAGE_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Cookie: sessionKey=$SESSION_KEY" \
    -H "Accept: application/json" \
    "$API_BASE/organizations/$ORG_ID/usage" 2>/dev/null)

USAGE_CODE=$(echo "$USAGE_RESPONSE" | tail -1)
USAGE_BODY=$(echo "$USAGE_RESPONSE" | sed '$d')

if [ "$USAGE_CODE" = "200" ]; then
    print_ok "Credentials verified!"
    echo ""

    # Parse and display current usage
    FIVE_HOUR=$(echo "$USAGE_BODY" | grep -oE '"five_hour"\s*:\s*\{[^}]*\}' | grep -oE '"utilization"\s*:\s*[0-9.]+' | grep -oE '[0-9.]+')
    SEVEN_DAY=$(echo "$USAGE_BODY" | grep -oE '"seven_day"\s*:\s*\{[^}]*\}' | head -1 | grep -oE '"utilization"\s*:\s*[0-9.]+' | grep -oE '[0-9.]+')

    echo "  Current usage:"
    if [ -n "$FIVE_HOUR" ]; then
        echo -e "    5-hour limit:  ${BOLD}${FIVE_HOUR}%${RESET}"
    fi
    if [ -n "$SEVEN_DAY" ]; then
        echo -e "    7-day limit:   ${BOLD}${SEVEN_DAY}%${RESET}"
    fi
elif [ "$USAGE_CODE" = "401" ] || [ "$USAGE_CODE" = "403" ]; then
    print_err "Authentication failed (HTTP $USAGE_CODE). Session key may have expired."
    echo ""
    echo "    Options:"
    echo "    • Re-extract a fresh sessionKey from browser cookies and run ./setup.sh again"
    echo "    • Or continue anyway — the widget will show 'Session Expired' and prompt you to update"
    echo ""
    read -r -p "Save credentials anyway? [y/N] " SAVE_ANYWAY
    if [[ "$SAVE_ANYWAY" != "y" && "$SAVE_ANYWAY" != "Y" ]]; then
        print_err "Setup cancelled. Run ./setup.sh with a fresh session key."
        exit 1
    fi
    print_warn "Saving with unvalidated credentials — update the session key in Settings when ready."
elif [ "$USAGE_CODE" = "404" ]; then
    print_warn "Organization not found (HTTP 404). The org ID may be incorrect."
    echo ""
    read -r -p "Enter org ID manually? [Y/n] " FIX_ORG
    if [[ "$FIX_ORG" != "n" && "$FIX_ORG" != "N" ]]; then
        prompt_manual_org_id
    else
        print_err "Setup cancelled. Run ./setup.sh to try again."
        exit 1
    fi
else
    print_warn "Could not validate (HTTP $USAGE_CODE). Saving credentials anyway — the widget will retry."
fi

# ============================================================
# Step 4: Save & Launch
# ============================================================
echo ""
echo -e "${DIM}Saving credentials to macOS UserDefaults...${RESET}"

defaults write "$APP_DOMAIN" "$SESSION_KEY_PREF" "$SESSION_KEY"
defaults write "$APP_DOMAIN" "$ORG_ID_PREF" "$ORG_ID"

print_ok "Credentials saved."
echo ""

# Launch or restart the app
if pgrep -f "ClaudeUsage" > /dev/null 2>&1; then
    read -r -p "ClaudeUsage is running. Restart to apply? [Y/n] " RESTART
    if [[ "$RESTART" != "n" && "$RESTART" != "N" ]]; then
        killall ClaudeUsage 2>/dev/null
        sleep 1
        if [ -d "build/ClaudeUsage.app" ]; then
            open build/ClaudeUsage.app
            print_ok "App restarted."
        else
            print_warn "App bundle not found. Run ./build.sh first, then open build/ClaudeUsage.app"
        fi
    fi
else
    read -r -p "Launch ClaudeUsage now? [Y/n] " LAUNCH
    if [[ "$LAUNCH" != "n" && "$LAUNCH" != "N" ]]; then
        if [ -d "build/ClaudeUsage.app" ]; then
            open build/ClaudeUsage.app
            print_ok "App launched."
        else
            print_warn "App bundle not found. Run ./build.sh first, then open build/ClaudeUsage.app"
        fi
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
echo -e "${DIM}Your widget should now display live Claude usage data.${RESET}"
echo -e "${DIM}Session keys expire periodically — run ./setup.sh again when that happens.${RESET}"
echo ""
