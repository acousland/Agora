import datetime
import email.utils
import pathlib
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

version, archive, signature_path = sys.argv[1:]
ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", ns)
signature = re.search(r'sparkle:edSignature="([^"]+)"', pathlib.Path(signature_path).read_text())
if not signature:
    raise SystemExit("Sparkle signature is missing")
with open("dist/Agora.app/Contents/Info.plist", "rb") as source:
    info = plistlib.load(source)
root = ET.Element("rss", version="2.0")
channel = ET.SubElement(root, "channel")
ET.SubElement(channel, "title").text = "Agora Updates"
ET.SubElement(channel, "link").text = "https://github.com/acousland/Agora"
ET.SubElement(channel, "description").text = "Updates for Agora, your local personal CRM."
ET.SubElement(channel, "language").text = "en-au"
item = ET.SubElement(channel, "item")
ET.SubElement(item, "title").text = f"Agora {version}"
ET.SubElement(item, "pubDate").text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, f"{{{ns}}}version").text = info["CFBundleVersion"]
ET.SubElement(item, f"{{{ns}}}shortVersionString").text = version
ET.SubElement(item, f"{{{ns}}}minimumSystemVersion").text = "14.0"
ET.SubElement(item, "description").text = pathlib.Path("RELEASE_NOTES.md").read_text()
ET.SubElement(item, "enclosure", {"url": f"https://github.com/acousland/Agora/releases/download/v{version}/Agora-{version}.dmg", "length": str(pathlib.Path(archive).stat().st_size), "type": "application/octet-stream", f"{{{ns}}}edSignature": signature.group(1)})
# Keep previous signed update enclosures, with the newest release first.
if pathlib.Path("appcast.xml").exists():
    previous = ET.parse("appcast.xml")
    for old in previous.findall("./channel/item"):
        if old.findtext(f"{{{ns}}}shortVersionString") != version:
            channel.append(old)
ET.indent(root)
ET.ElementTree(root).write("dist/appcast.xml", encoding="utf-8", xml_declaration=True)
