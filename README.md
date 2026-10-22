# GentleDesk Homebrew tap

Local desktop companion for GentleDesk / 智能桌面. Maintained by the product publisher, not Homebrew/core.

## Install and connect

Copy the complete command shown by GentleDesk → Connect desktop → Other installation options:

```sh
brew install haisheng/gentledesk/gentledesk && gentledesk setup YOUR_CHROME_EXTENSION_ID
```

If you already tapped this repository, `brew gentledesk YOUR_CHROME_EXTENSION_ID` installs the formula when needed and connects it. Homebrew may ask you to trust the formula or external command. No administrator access is required for the companion registration. Homebrew itself must already be installed.

Return to GentleDesk, confirm local data use, then choose your desktop folder. Only the exact extension ID you supply can connect. Files stay on your computer; the companion has no network-request code. Opening a target website/application may cause that separate program to access the network. Weather, AI and calendar connections in the extension have separate consent.

The ordinary downloaded installer also works without Homebrew: download the personalized package in the extension, unzip it and double-click **Install GentleDesk.command** on macOS or **Install GentleDesk.cmd** on Windows. Its extension ID is already filled in. A generic release ZIP needs an ID and is intended for manual/advanced installation.

## Update or remove

```sh
brew upgrade haisheng/gentledesk/gentledesk
gentledesk setup YOUR_CHROME_EXTENSION_ID
```

The setup command refreshes the current user's companion copy and exact ID registration. It preserves selected directories. To disconnect and remove that copy:

```sh
gentledesk uninstall
brew uninstall gentledesk
```

Original desktop files are never deleted. The helper is optional; the extension's web shortcuts and local calendar work without it.

## Release status

The Homebrew formula builds the macOS command-line helper from the versioned source archive using the system Swift compiler; it is not a downloaded GUI application and does not disable Gatekeeper. macOS 12+ source, Apple Silicon / Intel build support. Windows scripts are supplied separately; Windows validation runs in CI and still needs real-machine acceptance. Direct-download macOS binaries are ad-hoc signed; Developer ID signing/notarization remains a publisher release requirement.

No passwords, browser profiles, account tokens or telemetry are included in this repository. Source is published for inspection; an open-source license has not been selected. This publication does not transfer copyright.

Support: haisheng.loo@gmail.com
