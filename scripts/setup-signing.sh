#!/bin/bash
# Setup script for code signing and notarization secrets
# Run this locally to prepare your GitHub repository secrets

set -e

echo "=== Mac Input Stats — Signing Setup ==="
echo ""
echo "This script helps you configure the GitHub Secrets needed for"
echo "building signed and notarized DMGs via GitHub Actions."
echo ""
echo "You will need:"
echo "  1. An Apple Developer account with a 'Developer ID Application' certificate"
echo "  2. The certificate exported as a .p12 file from Keychain Access"
echo "  3. An app-specific password from https://appleid.apple.com"
echo ""

# Step 1: Certificate
echo "--- Step 1: Export your signing certificate ---"
echo ""
echo "Open Keychain Access → My Certificates → find 'Developer ID Application: ...'"
echo "Right-click → Export → save as a .p12 file with a password."
echo ""
read -p "Path to your .p12 file: " P12_PATH
read -sp "Password for the .p12: " P12_PASS
echo ""

if [ ! -f "$P12_PATH" ]; then
    echo "Error: File not found at $P12_PATH"
    exit 1
fi

B64=$(base64 -i "$P12_PATH")
echo ""
echo "✓ Certificate encoded. Set these GitHub Secrets:"
echo ""
echo "  BUILD_CERTIFICATE_BASE64 = (base64 output below)"
echo "  P12_PASSWORD = $P12_PASS"
echo ""
echo "--- base64 of certificate (copy this) ---"
echo "$B64"
echo "--- end ---"
echo ""

# Step 2: Notarization
echo "--- Step 2: Notarization credentials ---"
echo ""
echo "Go to https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
echo "Generate a new password for 'MacInputStats CI'."
echo ""
read -p "Apple ID (email): " APPLE_ID
read -sp "App-specific password: " APPLE_PW
echo ""
read -p "Team ID (10-char, from developer.apple.com/account): " TEAM_ID

echo ""
echo "✓ Set these additional GitHub Secrets:"
echo ""
echo "  APPLE_ID          = $APPLE_ID"
echo "  APPLE_ID_PASSWORD = $APPLE_PW"
echo "  APPLE_TEAM_ID     = $TEAM_ID"
echo ""
echo "=== Done! Push a tag (e.g. git tag v1.0.0 && git push --tags) to trigger a build. ==="
