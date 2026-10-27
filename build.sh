#!/bin/sh
# Re-execute with bash if run directly by /bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 1. Check if rojo is installed
if ! command -v rojo &> /dev/null; then
    echo "❌ Rojo is not installed."
    echo "💡 Please install Rojo using:"
    echo "   cargo install rojo"
    echo "   or download prebuilt binaries from: https://github.com/rojo-rbx/rojo/releases"
    exit 1
fi

# 2. Build game.rbxl with rojo
echo "🔨 Building game.rbxl with Rojo..."
rojo build -o game.rbxl

# 3. Print file size
if [ -f game.rbxl ]; then
    FILE_SIZE=$(ls -lh game.rbxl | awk '{print $5}')
    echo "✅ Build complete! Generated game.rbxl (${FILE_SIZE})"
else
    echo "❌ Build failed: game.rbxl was not generated."
    exit 1
fi

# 4 & 5. Publish if environment variables are set, otherwise print instructions
if [ -n "${ROBLOX_UNIVERSE_ID:-}" ] && [ -n "${ROBLOX_PLACE_ID:-}" ] && [ -n "${ROBLOX_API_KEY:-}" ]; then
    echo "🚀 Publishing game.rbxl to Roblox Open Cloud API..."

    PUBLISH_URL="https://apis.roblox.com/universes/v1/${ROBLOX_UNIVERSE_ID}/places/${ROBLOX_PLACE_ID}/versions?versionType=Published"
    
    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$PUBLISH_URL" \
        -H "x-api-key: ${ROBLOX_API_KEY}" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@game.rbxl")

    HTTP_BODY=$(echo "$RESPONSE" | sed -e '$d')
    HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1 | sed -e 's/HTTP_STATUS://')

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo "🎉 Successfully published to Roblox! (HTTP ${HTTP_STATUS})"
        if [ -n "$HTTP_BODY" ]; then
            echo "📄 Response: ${HTTP_BODY}"
        fi
    else
        echo "❌ Failed to publish to Roblox. (HTTP ${HTTP_STATUS})"
        if [ -n "$HTTP_BODY" ]; then
            echo "📄 Response: ${HTTP_BODY}"
        fi
        exit 1
    fi
else
    echo "ℹ️  Roblox publish credentials not detected. Skipping upload."
    echo "💡 To automatically publish to Roblox, set the following environment variables:"
    echo "   export ROBLOX_UNIVERSE_ID=\"<your-universe-id>\""
    echo "   export ROBLOX_PLACE_ID=\"<your-place-id>\""
    echo "   export ROBLOX_API_KEY=\"<your-api-key>\""
fi
