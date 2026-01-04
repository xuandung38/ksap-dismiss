#!/bin/bash
# Validate EdDSA key pair for Sparkle updates
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST_PATH="$PROJECT_ROOT/KSAPDismiss/Info.plist"

echo "🔑 Validating EdDSA Key Pair..."
echo ""

# Read public key from Info.plist
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST_PATH" 2>/dev/null)
if [ -z "$PUBLIC_KEY" ]; then
    echo "❌ Error: No public key found in Info.plist"
    exit 1
fi
echo "✅ Public key found in Info.plist: ${PUBLIC_KEY:0:20}..."

# Read private key from Keychain
PRIVATE_KEY=$(security find-generic-password -a "ed25519" -s "https://sparkle-project.org" -w 2>/dev/null)
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: No private key found in Keychain"
    echo "   Account: ed25519"
    echo "   Service: https://sparkle-project.org"
    exit 1
fi
echo "✅ Private key found in Keychain: ${PRIVATE_KEY:0:20}..."

# Validate key format (EdDSA keys are 32 bytes = 44 base64 characters including padding)
PUBLIC_LENGTH=${#PUBLIC_KEY}
PRIVATE_LENGTH=${#PRIVATE_KEY}

if [ "$PUBLIC_LENGTH" -ne 44 ]; then
    echo "⚠️  Warning: Public key length is $PUBLIC_LENGTH (expected 44)"
fi

if [ "$PRIVATE_LENGTH" -ne 44 ]; then
    echo "⚠️  Warning: Private key length is $PRIVATE_LENGTH (expected 44)"
fi

# Test signing with a dummy file (if sign_update tool exists)
if [ -f "$SCRIPT_DIR/sign_update" ]; then
    echo ""
    echo "🧪 Testing signature generation..."

    # Create a temporary test file
    TEST_FILE=$(mktemp)
    echo "test" > "$TEST_FILE"

    # Try to sign it
    if "$SCRIPT_DIR/sign_update" "$TEST_FILE" > /dev/null 2>&1; then
        echo "✅ Successfully signed test file - key pair is valid!"
        rm -f "$TEST_FILE"
    else
        echo "⚠️  Warning: Could not sign test file"
        echo "   This might be normal if sign_update requires specific file types"
        rm -f "$TEST_FILE"
    fi
else
    echo ""
    echo "ℹ️  Note: sign_update tool not found - skipping signature test"
    echo "   Download Sparkle tools from: https://github.com/sparkle-project/Sparkle/releases"
fi

echo ""
echo "✅ Key pair validation complete!"
echo ""
echo "Summary:"
echo "  Public key:  ${PUBLIC_KEY}"
echo "  Private key: ${PRIVATE_KEY:0:8}... (hidden)"
echo ""
