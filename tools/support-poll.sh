#!/usr/bin/env bash
# Print BonusRollGate support traffic that has not been handled yet: Discord
# #support and #ideas, plus open GitHub issues.
#
#   support-poll.sh            list everything new since the last ack
#   support-poll.sh --ack ID   mark Discord messages up to ID as handled
#   support-poll.sh --reply ID TEXT   reply in-channel to Discord message ID
#
# State is a single message id in discord-poll.state, so a crashed run does not
# lose messages: nothing advances until --ack. GitHub issues are listed by
# whether the last comment came from someone other than the maintainer, so they
# need no state of their own.
#
# Reading other people's message content needs Message Content Intent enabled
# on the Bot tab. Without it every content field comes back empty.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/discord.env"

API="https://discord.com/api/v10"
AUTH=(-H "Authorization: Bot $DISCORD_TOKEN" -H "Content-Type: application/json")
SUPPORT=1543768120655880264
IDEAS=1543768122434129960
STATE="$HERE/discord-poll.state"

case ${1:-} in
    --ack)
        printf '%s' "${2:?usage: --ack <message id>}" > "$STATE"
        echo "Acked up to ${2}."
        exit 0
        ;;
    --reply)
        id=${2:?usage: --reply <message id> <text>}
        text=${3:?usage: --reply <message id> <text>}
        jq -n --arg c "$text" --arg m "$id" \
            '{content: $c, message_reference: {message_id: $m}}' > /tmp/discord-reply.json
        curl -sS -f -X POST "${AUTH[@]}" --data-binary @/tmp/discord-reply.json \
            "$API/channels/$SUPPORT/messages" | jq -r '"Replied: \(.id)"'
        exit 0
        ;;
esac

after=$(cat "$STATE" 2>/dev/null || echo "")
found=0

for ch in "$SUPPORT" "$IDEAS"; do
    q="limit=50"
    [[ -n $after ]] && q="$q&after=$after"
    msgs=$(curl -sS -f "${AUTH[@]}" "$API/channels/$ch/messages?$q")
    # Oldest first, and never report the bot's own posts back to itself.
    count=$(jq '[.[] | select(.author.bot != true)] | length' <<<"$msgs")
    found=$((found + count))
    jq -r 'reverse | .[] | select(.author.bot != true) |
        "---\nchannel: \($ch)\nid: \(.id)\nfrom: \(.author.username)\nat: \(.timestamp)\n\(.content)"' \
        --arg ch "$ch" <<<"$msgs"
done

if (( found == 0 )); then
    echo "No new Discord messages."
fi

# Open issues whose last word came from someone else. An issue the maintainer
# answered last is waiting on the reporter, not on us.
echo
echo "=== GitHub issues awaiting a reply ==="
gh issue list --repo "${REPO:-JoesphG/BonusRollGate}" --state open \
    --json number,title,author,updatedAt,comments \
    --jq '.[] | select((.comments | length) == 0 or (.comments[-1].author.login != "JoesphG"))
        | "---\nissue: #\(.number)\ntitle: \(.title)\nfrom: \(.author.login)\nupdated: \(.updatedAt)\ncomments: \(.comments | length)"' \
    || echo "gh unavailable or not authenticated."
