#!/usr/bin/python3
"""Capture or restore Rex's appearance preferences without touching server settings.

Usage:
  python3 ~/.config/rex/appearance.py capture
  python3 ~/.config/rex/appearance.py apply

Capture is safe while Rex is open. Apply after quitting the Rex app yourself;
the next app launch reads these preferences. This command never stops Rex.
The Go Mono Tmux font must already be installed on the destination Mac.
"""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess

DOMAIN = "com.superlogical.rex"
SNAPSHOT = Path(__file__).resolve().with_name("appearance.json")
KEYS = (
    "animationStyle", "appearance", "balancesSplitsOnCreation", "customThemes",
    "darkThemeID", "focusFollowsMouse", "inactivePaneFadeMode", "interfaceStyle",
    "lightThemeID", "paneDensity", "showsActivePaneBorder", "showsPaneHeaders",
    "sidebarCollapsed", "sidebarPosition", "sidebarShowsActivity", "sidebarWidth",
    "tabIconCount", "tabIconTintMode", "tabStyle", "tabsFillAvailableSpace",
    "terminalCharacterSpacing", "terminalCopyAnimation",
    "terminalCursorBlinkIntervalMilliseconds", "terminalCursorBlinkUsesCustomInterval",
    "terminalCursorStyleForced", "terminalFontName", "terminalFontPointSize",
    "terminalFontSmoothing", "terminalImproveTextContrast", "terminalPaddingColor",
    "terminalPaddingX", "terminalPaddingY", "terminalSelectionRoundedCorners",
    "terminalSmoothScrolling", "terminalUseThemePalette", "terminalUsesDisplayP3",
    "tintsPanesWithProgramBackground", "usesPaneGlass", "usesStandardInactiveWindowPaneStyles",
)
ALLOWED = {"Workspace." + key for key in KEYS}


def preferences():
    result = subprocess.run(["/usr/bin/defaults", "export", DOMAIN, "-"],
                            capture_output=True)
    if result.returncode:
        return {}
    return plistlib.loads(result.stdout)


def capture():
    current = preferences()
    if not current:
        raise SystemExit("No Rex preferences found; the appearance snapshot was left intact.")
    saved = {key: value for key, value in current.items() if key in ALLOWED}
    selected = {saved.get("Workspace.lightThemeID"), saved.get("Workspace.darkThemeID")}
    saved["Workspace.customThemes"] = [
        theme for theme in json.loads(current.get("Workspace.customThemes", b"[]"))
        if theme["id"] in selected
    ]
    SNAPSHOT.write_text(json.dumps(saved, indent=2, sort_keys=True) + "\n")
    print("Captured appearance preferences in", SNAPSHOT)


def apply():
    running = subprocess.run(
        ["/usr/bin/pgrep", "-f", r"^/Applications/Rex[^/]*\.app/Contents/MacOS/"],
        capture_output=True,
    )
    if running.returncode == 0:
        raise SystemExit("Quit the Rex app before applying its appearance preferences; it is still running.")
    saved = json.loads(SNAPSHOT.read_text())
    unknown = set(saved) - ALLOWED
    if unknown:
        raise SystemExit("Unrecognized preference keys: " + ", ".join(sorted(unknown)))
    current = preferences()
    existing = json.loads(current.get("Workspace.customThemes", b"[]"))
    themes = {theme["id"]: theme for theme in existing}
    themes.update({theme["id"]: theme for theme in saved.get("Workspace.customThemes", [])})
    for key, value in saved.items():
        if key == "Workspace.customThemes":
            args = ["-data", json.dumps(list(themes.values()), separators=(",", ":")).encode().hex()]
        elif isinstance(value, bool):
            args = ["-bool", str(value).lower()]
        elif isinstance(value, int):
            args = ["-int", str(value)]
        elif isinstance(value, float):
            args = ["-float", str(value)]
        elif isinstance(value, str):
            args = ["-string", value]
        else:
            raise SystemExit("Unsupported value for " + key)
        subprocess.run(["/usr/bin/defaults", "write", DOMAIN, key, *args], check=True)
    print("Appearance preferences restored. They will load when you next open Rex.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("operation", choices=("capture", "apply"))
    args = parser.parse_args()
    capture() if args.operation == "capture" else apply()
