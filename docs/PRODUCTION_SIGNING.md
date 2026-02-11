# Production Code Signing & Notarization Setup

This guide walks you through setting up production-ready code signing and notarization for Arcmark.

## Prerequisites

- ✅ Active Apple Developer Account ($99/year)
- ✅ macOS 10.15+ (for notarization)
- ✅ Xcode Command Line Tools installed

## Step 1: Get Your Developer ID Certificate

You need a "Developer ID Application" certificate to sign apps distributed outside the Mac App Store.

### Option A: Create via Xcode (Recommended)

1. Open **Xcode**
2. Go to **Xcode → Settings** (or Preferences)
3. Click **Accounts** tab
4. Click **+** to add your Apple ID (if not already added)
5. Select your Apple ID, then click **Manage Certificates**
6. Click **+** and select **Developer ID Application**
7. Xcode will request and install the certificate

### Option B: Create via Apple Developer Portal

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Click **+** to create a new certificate
3. Select **Developer ID Application** under "Software"
4. Follow the instructions to create a Certificate Signing Request (CSR):
   - Open **Keychain Access**
   - Menu: **Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority**
   - Enter your email, select "Saved to disk"
   - Save the CSR file
5. Upload the CSR file
6. Download the certificate and double-click to install it

### Verify Installation

Run this command to verify your certificate is installed:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You should see output like:
```
1) ABC123... "Developer ID Application: Your Name (TEAM_ID)"
```

**Copy the full certificate name** (including quotes) - you'll need it later.

## Step 2: Find Your Team ID

Your Team ID is required for notarization.

### Find Team ID:

**Option 1: From certificate output above**
```
"Developer ID Application: Your Name (ABC123XYZ)"
                                        ^^^^^^^^^ This is your Team ID
```

**Option 2: From Apple Developer portal**
1. Go to https://developer.apple.com/account
2. Click **Membership** in the sidebar
3. Your Team ID is listed there

**Save this Team ID** - you'll need it for notarization.

## Step 3: Create App-Specific Password for Notarization

Notarization requires an app-specific password (not your Apple ID password).

1. Go to https://appleid.apple.com/account/manage
2. Sign in with your Apple ID
3. In the **Security** section, click **App-Specific Passwords**
4. Click **+** or **Generate Password**
5. Enter a label: "Arcmark Notarization"
6. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)

**IMPORTANT**: Save this password - you won't see it again!

## Step 4: Configure Notarization Credentials

Create a credentials file (git-ignored) to store your notarization info:

```bash
# Create the config file
cat > .notarization-config <<'EOF'
# Notarization credentials for Arcmark
# This file is git-ignored - never commit it!

# Your Apple ID email
APPLE_ID="your-email@example.com"

# Your Team ID (10 characters, found in Step 2)
TEAM_ID="ABC123XYZ"

# Your app-specific password (from Step 3)
# Format: xxxx-xxxx-xxxx-xxxx
APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

# Your Developer ID certificate name (from Step 1)
# Include the full name in quotes
SIGNING_IDENTITY="Developer ID Application: Your Name (ABC123XYZ)"
EOF

# Make sure it's git-ignored
echo ".notarization-config" >> .gitignore
```

**Fill in your actual values** in `.notarization-config`:
- Replace `your-email@example.com` with your Apple ID
- Replace `ABC123XYZ` with your Team ID
- Replace `xxxx-xxxx-xxxx-xxxx` with your app-specific password
- Replace the `SIGNING_IDENTITY` with your full certificate name

## Step 5: Test the Configuration

Run this command to verify your credentials:

```bash
# Test that your certificate is accessible
security find-identity -v -p codesigning | grep "$(cat .notarization-config | grep SIGNING_IDENTITY | cut -d'"' -f2)"

# Test notarytool access (this should succeed without submitting anything)
source .notarization-config
xcrun notarytool history --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD"
```

If both commands succeed, you're ready to build!

## Step 6: Build with Production Signing

Now you can build with proper code signing:

```bash
# Build app only (with Developer ID signing)
./scripts/build.sh --production

# Build app and create notarized DMG
./scripts/build.sh --production --dmg
```

The `--production` flag will:
- ✅ Sign with your Developer ID certificate
- ✅ Enable hardened runtime
- ✅ Submit for notarization (if building DMG)
- ✅ Wait for notarization approval (~5 minutes)
- ✅ Staple the notarization ticket to the app

## What Happens During Notarization

1. **Build**: App is built and signed with Developer ID
2. **Upload**: Signed app is zipped and uploaded to Apple
3. **Scan**: Apple scans for malware (~2-5 minutes)
4. **Approval**: If clean, Apple issues a notarization ticket
5. **Stapling**: Ticket is attached to the app (works offline)

## Troubleshooting

### "No identity found" Error

**Problem**: Certificate not installed or not found

**Solution**:
```bash
# List all signing identities
security find-identity -v -p codesigning

# If empty, install your certificate via Xcode (Step 1)
```

### "Invalid Credentials" Error

**Problem**: Apple ID, Team ID, or app password is incorrect

**Solution**:
- Verify your Apple ID email is correct
- Verify Team ID is exactly 10 characters
- Generate a new app-specific password (Step 3)
- Update `.notarization-config` with correct values

### Notarization Fails with "Invalid" Status

**Problem**: App has issues that prevent notarization

**Solution**:
```bash
# Get detailed notarization log
source .notarization-config
xcrun notarytool log <submission-id> --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD"
```

Common issues:
- Missing hardened runtime entitlements
- Unsigned dynamic libraries
- Invalid Info.plist values

### "Connection to Apple Failed"

**Problem**: Network issue or Apple services down

**Solution**:
- Check your internet connection
- Check https://developer.apple.com/system-status/
- Try again in a few minutes

## Security Best Practices

### Protecting Credentials

✅ **DO**:
- Keep `.notarization-config` in `.gitignore`
- Use app-specific passwords (never your Apple ID password)
- Rotate app-specific passwords periodically
- Store backups securely (password manager)

❌ **DON'T**:
- Commit credentials to git
- Share credentials with others
- Use your Apple ID password for notarization
- Store credentials in scripts

### CI/CD Considerations

If you plan to use CI/CD (GitHub Actions, etc.):

1. Store credentials in CI secrets (not in code)
2. Use `xcrun notarytool store-credentials` to store in keychain
3. Reference stored credentials by name:
   ```bash
   xcrun notarytool submit app.zip --keychain-profile "arcmark-notarization"
   ```

## Verification After Distribution

### Test Signed App

```bash
# Check code signature
codesign -dvvv .build/bundler/Arcmark.app

# Check notarization
spctl -a -vvv -t install .build/bundler/Arcmark.app

# Should output: "accepted" and "source=Notarized Developer ID"
```

### Test User Experience

1. Build and create DMG: `./scripts/build.sh --production --dmg`
2. Copy DMG to another Mac (or a different user account)
3. Mount DMG and drag app to Applications
4. Launch the app
5. **Expected**: App launches without warnings ✨
6. **Not expected**: Any security warnings or prompts

## Cost Summary

- **Apple Developer Program**: $99/year (required)
- **Notarization**: Free (included in Developer Program)
- **Build time**: +5 minutes per build (for notarization)

## Next Steps

After setting up production signing:

1. ✅ Test locally on your machine
2. ✅ Test on a friend's Mac (fresh install)
3. ✅ Verify no security warnings appear
4. ✅ Distribute to beta testers
5. 🎉 Launch to public!

## Resources

- [Apple: Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Apple: Customizing the Notarization Workflow](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow)
- [Apple: Resolving Common Notarization Issues](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/resolving_common_notarization_issues)
