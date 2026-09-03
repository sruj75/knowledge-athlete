# dmgbuild settings for the Intentive desktop installer.
# Usage: dmgbuild -s dmgbuild_settings.py -D app_path=/path/to/Intentive.app \
#   -D app_name=Intentive "Intentive" output.dmg
#
# This replaces create-dmg + AppleScript (which fails in CI due to --skip-jenkins).
# dmgbuild writes .DS_Store directly — no Finder/AppleScript needed.

import os

app_path = defines.get("app_path", "Intentive.app")
app_name = defines.get("app_name", "Intentive")
# __file__ is not set when executed by dmgbuild; use defines or fall back to cwd
_script_dir = defines.get("assets_dir", os.path.join(os.getcwd(), "dmg-assets"))
bg_path = defines.get("background", os.path.join(_script_dir, "background.png"))
icon_path = defines.get("volume_icon", None)

# Volume settings
format = "UDBZ"  # bzip2 compressed
size = None  # auto-calculate
filesystem = "HFS+"

# Files to include
files = [app_path]
symlinks = {"Applications": "/Applications"}

# Window settings
# dmgbuild automatically compiles background.png with background@2x.png into a
# multi-resolution TIFF that Finder selects at the display's native scale.
background = bg_path
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

window_rect = ((200, 120), (652, 381))
default_view = "icon-view"

icon_size = 112
text_size = 12

# Icon positions match the approved warm, centered installer composition.
icon_locations = {
    app_name + ".app": (198, 190),
    "Applications": (474, 190),
}

# Hiding the extension attaches com.apple.FinderInfo to the signed app bundle,
# which makes codesign --deep --strict reject the app copied into the DMG.
hide_extensions = []

# Volume icon
if icon_path:
    badge_icon = icon_path
