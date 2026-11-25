# Command X v1.1.1 (Glass Edition)

Fork of [EnableStartup/command-x](https://github.com/EnableStartup/command-x) with the community fixes from upstream PR #1 (marton78) merged in.

## Changes
- Bugfixes from PR #1: AppleScript error handling, hotkey cleanup, logging, unit tests, Launch at Login handling
- New UI in Liquid Glass (macOS 26+), system materials on macOS 12 to 25
- App icon and menu bar icon: the macOS Command key symbol
- New cut sound: paper crumple (synthesized, see `tools/make_crumple_sound.py`)
- Minimum macOS 12.0 (Xcode 27 no longer builds for 11)
- Open Accessibility Settings now also adds Command X to the Accessibility list (you still switch it on)
- Release build via `scripts/build-dmg.sh` and the `Release` GitHub Actions workflow

## Installation
1. Download `CommandX-1.1.1.dmg` (or the `.zip`) from the release page and drag Command X to Applications.
2. The app is ad-hoc signed, not notarized. On first launch: System Settings > Privacy & Security > Open Anyway.
3. Allow Accessibility and Automation (Finder, System Events) when asked.

Verify the download against `SHA256SUMS.txt`.

## Usage
Select files in Finder, Command+X to cut (crumple sound), Command+V in the target folder to move them.

## License
GPL-3.0, see LICENSE.
