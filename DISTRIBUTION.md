# ManeAI Distribution Guide

This guide explains how to build and distribute ManeAI with its embedded Node.js sidecar.

## Prerequisites

1. **Apple Developer Program** ($99/year)
   - Sign up at: https://developer.apple.com/programs/
   - Required for Developer ID certificate and notarization

2. **Developer ID Certificate**
   - Go to Xcode → Settings → Accounts → Manage Certificates
   - Create a "Developer ID Application" certificate

3. **Dependencies**
   - Node.js 20+ (for building sidecar)
   - pnpm (`npm install -g pnpm`)
   - Xcode 15+

## Build Process

### Step 1: Build the Sidecar

Run the distribution build script:

```bash
# For development/testing (no code signing)
./scripts/build-for-distribution.sh

# For distribution (with code signing)
./scripts/build-for-distribution.sh --sign "Developer ID Application: Your Name (TEAM_ID)"

# For Intel Macs (if needed)
./scripts/build-for-distribution.sh --arch x64 --sign "Developer ID Application: Your Name (TEAM_ID)"
```

This script will:
- Download Node.js runtime for macOS
- Build the NestJS sidecar
- Copy everything to `ManeAI/ManePaw/Resources/`
- Sign all native binaries (if signing identity provided)

### Step 2: Add Resources to Xcode Project

1. Open `ManePaw.xcodeproj` in Xcode

2. In the Project Navigator, right-click on "ManePaw" folder → "Add Files to ManePaw"

3. Select the `Resources` folder and ensure:
   - ✅ "Copy items if needed" is **unchecked** (use folder reference)
   - ✅ "Create folder references" is selected
   - ✅ "Add to targets: ManePaw" is checked

4. Verify in Build Phases → "Copy Bundle Resources" that you see:
   - `Resources/node/`
   - `Resources/sidecar/`

### Step 3: Configure Signing in Xcode

1. Select the ManePaw target
2. Go to **Signing & Capabilities**
3. Configure:
   - **Team**: Your Apple Developer team
   - **Signing Certificate**: Developer ID Application
   - **Hardened Runtime**: Enabled (should be automatic)

### Step 4: Archive and Notarize

1. In Xcode, select **Product → Archive**
2. Wait for archive to complete
3. In the Organizer window:
   - Select the archive
   - Click **Distribute App**
   - Choose **Direct Distribution**
   - Select **Upload** (for notarization)
   - Wait for notarization (5-15 minutes)
   - Click **Export** when complete

### Step 5: Create DMG

After exporting the notarized `.app`:

```bash
# Simple DMG
hdiutil create -volname "Mane AI" \
  -srcfolder /path/to/ManePaw.app \
  -ov -format UDZO \
  ManeAI-v1.dmg

# Or use create-dmg for a prettier installer
# brew install create-dmg
create-dmg \
  --volname "Mane AI" \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 450 200 \
  --icon "ManePaw.app" 150 200 \
  "ManeAI-v1.dmg" \
  "/path/to/ManePaw.app"
```

### Step 6: Upload to GitHub Release

```bash
gh release upload v1 ManeAI-v1.dmg --clobber
```

## App Bundle Structure

After building, your app bundle should look like:

```
ManePaw.app/
├── Contents/
│   ├── MacOS/
│   │   └── ManePaw              # Main executable
│   ├── Resources/
│   │   ├── node/
│   │   │   └── node             # Bundled Node.js runtime
│   │   └── sidecar/
│   │       ├── dist/
│   │       │   └── main.js      # Compiled NestJS app
│   │       ├── node_modules/    # Production dependencies
│   │       └── package.json
│   ├── Info.plist
│   └── _CodeSignature/
└── ...
```

## Entitlements

### Main App (`ManePaw.entitlements`)

The main app needs these entitlements:

- `com.apple.security.app-sandbox` - Required for App Store / recommended for direct
- `com.apple.security.network.client` - Talk to sidecar
- `com.apple.security.network.server` - Sidecar listens on localhost
- `com.apple.security.cs.allow-unsigned-executable-memory` - For Node.js JIT
- `com.apple.security.cs.disable-library-validation` - For native modules

### Sidecar (`Sidecar.entitlements`)

Used when signing Node.js and native modules:

- `com.apple.security.cs.allow-jit` - V8 JIT compilation
- `com.apple.security.cs.allow-unsigned-executable-memory` - Node.js requirement
- `com.apple.security.cs.disable-library-validation` - Native modules

## Troubleshooting

### "Node.js not found"

1. Check that `Resources/node/node` exists in the app bundle
2. Verify the binary is executable: `chmod +x Resources/node/node`
3. Check Console.app for sandbox violations

### "Sidecar won't start"

1. Check that `Resources/sidecar/dist/main.js` exists
2. Verify node_modules are present: `Resources/sidecar/node_modules/`
3. Check sidecar logs in the app

### "Native module loading failed"

1. Ensure all `.node` files are signed
2. Check entitlements include `disable-library-validation`
3. Rebuild native modules for the correct architecture (arm64 vs x64)

### Notarization Fails

1. Check all executables are signed with hardened runtime
2. Ensure no unsigned binaries in the bundle
3. Review notarization log: `xcrun notarytool log <submission-id>`

## Universal Binary (Apple Silicon + Intel)

To support both architectures:

1. Build sidecar twice (once for each arch)
2. Use `lipo` to create universal Node.js binary
3. Native modules need universal binaries too

```bash
# Create universal Node.js
lipo -create node-arm64 node-x64 -output node

# For native modules, rebuild with:
npm rebuild --arch=arm64
npm rebuild --arch=x64
```

## Quick Reference

| Command | Description |
|---------|-------------|
| `./scripts/build-for-distribution.sh` | Build sidecar (no signing) |
| `./scripts/build-for-distribution.sh --sign "..."` | Build with signing |
| `pnpm run build:sidecar` | Build sidecar only (in backend dir) |
| `gh release upload v1 file.dmg` | Upload to GitHub release |
