#!/usr/bin/env bash
# One-off Discord server setup for BonusRollGate support.
#
# Creates two categories, five channels, a @Maintainer role and an
# #announcements webhook, then prints the webhook URL for the GitHub side.
#
# Needs a bot in the server with Manage Channels + Manage Roles + Manage
# Webhooks. Reads credentials from discord.env beside this script:
#
#   DISCORD_TOKEN=...    bot token, no "Bot " prefix
#   DISCORD_GUILD=...    server id (right-click server -> Copy Server ID)
#
# Re-running creates duplicates. It is not idempotent; run it once.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/discord.env"

API="https://discord.com/api/v10"
AUTH=(-H "Authorization: Bot $DISCORD_TOKEN" -H "Content-Type: application/json")

# Permission bits.
VIEW=1024                    # VIEW_CHANNEL
SEND=2048                    # SEND_MESSAGES
HISTORY=65536                # READ_MESSAGE_HISTORY
REACT=64                     # ADD_REACTIONS
THREADS=34359738368          # CREATE_PUBLIC_THREADS
SEND_THREADS=274877906944    # SEND_MESSAGES_IN_THREADS
MENTION=131072               # MENTION_EVERYONE
MANAGE_MSG=8192              # MANAGE_MESSAGES
MANAGE_THREADS=17179869184   # MANAGE_THREADS

# Read-only category: look and react, do not post.
INFO_ALLOW=$((VIEW + HISTORY + REACT))
INFO_DENY=$((SEND + THREADS + MENTION))

# Support category: post and open threads, never ping the server.
TALK_ALLOW=$((VIEW + SEND + HISTORY + REACT + THREADS + SEND_THREADS))
TALK_DENY=$((MENTION))

# @everyone's role id is the guild id.
EVERYONE="$DISCORD_GUILD"

api() { # method path [json]
    local method=$1 path=$2 body=${3:-}
    local out code
    if [[ -n $body ]]; then
        out=$(curl -sS -w '\n%{http_code}' -X "$method" "${AUTH[@]}" -d "$body" "$API$path")
    else
        out=$(curl -sS -w '\n%{http_code}' -X "$method" "${AUTH[@]}" "$API$path")
    fi
    code=$(tail -n1 <<<"$out")
    body=$(sed '$d' <<<"$out")
    if [[ $code != 2* ]]; then
        echo "HTTP $code on $method $path" >&2
        echo "$body" >&2
        exit 1
    fi
    echo "$body"
}

overwrites() { # allow deny
    jq -nc --arg id "$EVERYONE" --arg a "$1" --arg d "$2" \
        '[{id: $id, type: 0, allow: $a, deny: $d}]'
}

category() { # name allow deny
    api POST "/guilds/$DISCORD_GUILD/channels" \
        "$(jq -nc --arg n "$1" --argjson o "$(overwrites "$2" "$3")" \
            '{name: $n, type: 4, permission_overwrites: $o}')" | jq -r .id
}

channel() { # name parent_id topic
    api POST "/guilds/$DISCORD_GUILD/channels" \
        "$(jq -nc --arg n "$1" --arg p "$2" --arg t "$3" \
            '{name: $n, type: 0, parent_id: $p, topic: $t}')" | jq -r .id
}

echo "Creating categories..."
INFO=$(category "information" "$INFO_ALLOW" "$INFO_DENY")
TALK=$(category "support" "$TALK_ALLOW" "$TALK_DENY")

echo "Creating channels..."
ANNOUNCE=$(channel "announcements" "$INFO" "Release notes. Posted automatically on every BonusRollGate release.")
channel "start-here" "$INFO" "What BonusRollGate does and how to report a bug." >/dev/null
channel "support" "$TALK" "Bug reports and help. Include your addon version from /brg status." >/dev/null
channel "ideas" "$TALK" "Feature requests." >/dev/null
channel "general" "$TALK" "Everything else." >/dev/null

echo "Creating @Maintainer role..."
api POST "/guilds/$DISCORD_GUILD/roles" \
    "$(jq -nc --argjson p "$((MANAGE_MSG + MANAGE_THREADS))" \
        '{name: "Maintainer", permissions: ($p|tostring), hoist: true, mentionable: false}')" \
    | jq -r '"  role id: \(.id)"'

echo "Creating #announcements webhook..."
HOOK=$(api POST "/channels/$ANNOUNCE/webhooks" '{"name":"GitHub Releases"}' | jq -r .url)

# 512x512 PNG, the same art as the CurseForge avatar. Needs Manage Guild.
echo "Setting the server icon..."
ICON="$HERE/../images/curseforge-avatar.png"
api PATCH "/guilds/$DISCORD_GUILD" \
    "$(jq -nc --arg d "data:image/png;base64,$(base64 -w0 "$ICON")" '{icon: $d}')" >/dev/null

echo
echo "Done."
echo "Webhook URL: $HOOK"
echo
echo "Assign yourself @Maintainer in Server Settings -> Members."
