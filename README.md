# Mac Disk Imager

Native macOS disk imaging utility inspired by Win32 Disk Imager.

**Version:** 1.0.0  
**Platform:** macOS 13 or later  
**Architectures:** Intel `x86_64` + Apple Silicon `arm64`

## Features

- Read a full USB, SD or eMMC device into an image file
- Write an image file to a removable device
- Verify device contents against an image
- Optional verification after writing
- Full-device imaging or imaging up to the end of the last detected partition
- Transfer progress and speed display
- Internal disks hidden from normal device selection
- Automatic unmount/eject handling
- Universal macOS application build
- Privileged helper installation on first use

## Build

Requirements:

- macOS 13+
- Xcode Command Line Tools
- Swift 5.9 or later

Build a universal application and DMG:

```bash
chmod +x build_app.sh create_dmg.sh
./build_app.sh --dmg
```

Output:

```text
dist/Mac Disk Imager.app
dist/Mac_Disk_Imager_1.0.0.dmg
```

To build only for the current host architecture:

```bash
UNIVERSAL=0 ./build_app.sh
```

## Code signing

Without a Developer ID certificate, the build script applies an ad-hoc signature. Gatekeeper may warn when the application is opened on another Mac.

For public distribution, set a valid `Developer ID Application` identity:

```bash
export DEVELOPER_ID_APP='Developer ID Application: YOUR NAME (TEAMID)'
./build_app.sh --dmg
```

## Notarization

Store notarization credentials once:

```bash
xcrun notarytool store-credentials "MacDiskImagerNotary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "APP-SPECIFIC-PASSWORD"
```

Then build, sign and notarize:

```bash
export DEVELOPER_ID_APP='Developer ID Application: YOUR NAME (TEAMID)'
export NOTARY_PROFILE='MacDiskImagerNotary'
./build_app.sh --dmg
```

The build scripts sign the app and DMG, submit the DMG to Apple, wait for the notarization result, and staple the ticket.

## Privileged helper

On first launch, the application can install its helper at:

```text
/Library/PrivilegedHelperTools/pl.madejak.MacDiskImagerHelper
```

macOS will request administrator authorization.

## Project structure

```text
Mac-Disk-Imager/
├── Package.swift
├── README.md
├── LICENSE
├── .gitignore
├── MyIcon.icns
├── build_app.sh
├── create_dmg.sh
└── Sources/
    ├── MacDiskImager/
    │   ├── MacDiskImagerApp.swift
    │   ├── ContentView.swift
    │   ├── ImagingController.swift
    │   ├── DiskService.swift
    │   ├── DiskDevice.swift
    │   └── Shell.swift
    └── MacDiskImagerHelper/
        └── main.swift
```

## GitHub releases

Do not commit generated `.dmg` files to the repository. Publish them under **GitHub Releases** instead.

Example release workflow:

```bash
gh release create v1.0.0 \
  dist/Mac_Disk_Imager_1.0.0.dmg \
  --title "Mac Disk Imager 1.0.0" \
  --notes "Initial macOS release."
```

## Safety

**WRITE permanently overwrites the selected device.** Always verify the disk identifier, model and capacity before starting a write operation. Keep backups of important data.

## License

MIT License. See [LICENSE](LICENSE).
