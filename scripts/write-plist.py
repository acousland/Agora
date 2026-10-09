import plistlib
import pathlib
import sys

destination, version, build = sys.argv[1:]
plist = {
    "CFBundleIdentifier": "au.com.acousland.Agora", "CFBundleName": "Agora", "CFBundleDisplayName": "Agora",
    "CFBundleExecutable": "Agora", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
    "CFBundleVersion": build, "CFBundleIconFile": "Agora", "LSMinimumSystemVersion": "14.0",
    "NSHighResolutionCapable": True, "NSPrincipalClass": "NSApplication",
    "NSHumanReadableCopyright": "Copyright © 2026 Aaron Cousland. MIT License.",
    "SUFeedURL": "https://raw.githubusercontent.com/acousland/Agora/main/appcast.xml",
    "SUPublicEDKey": pathlib.Path("Assets/sparkle-public-key").read_text().strip(),
    "SUEnableAutomaticChecks": True, "SUVerifyUpdateBeforeExtraction": True,
    "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}
}
with open(destination, "wb") as output:
    plistlib.dump(plist, output)
