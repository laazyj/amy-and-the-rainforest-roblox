#!/usr/bin/env python3
"""
Builds AmyAndTheRainforest.rbxlx from the Lua sources in src/.

The .rbxlx is a plain-XML Roblox place file that Roblox Studio can open
directly (File > Open from File). It contains only the scripts -- the
whole world is built procedurally by WorldBuilder when you press Play.

Usage:
    python3 tools/build_rbxlx.py
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(ROOT, "AmyAndTheRainforest.rbxlx")

_referent_counter = 0


def next_referent():
    global _referent_counter
    _referent_counter += 1
    return "RBX%08d" % _referent_counter


def cdata(text):
    """Wrap text in CDATA, safely splitting any ']]>' sequences."""
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def script_item(class_name, name, source_path):
    with open(source_path, "r", encoding="utf-8") as f:
        source = f.read()
    return (
        '<Item class="%s" referent="%s">\n'
        "<Properties>\n"
        '<string name="Name">%s</string>\n'
        '<ProtectedString name="Source">%s</ProtectedString>\n'
        "</Properties>\n"
        "</Item>\n" % (class_name, next_referent(), name, cdata(source))
    )


def service_item(class_name, children_xml):
    return (
        '<Item class="%s" referent="%s">\n'
        "<Properties>\n"
        '<string name="Name">%s</string>\n'
        "</Properties>\n"
        "%s"
        "</Item>\n" % (class_name, next_referent(), class_name, children_xml)
    )


def main():
    src = os.path.join(ROOT, "src")

    replicated = service_item(
        "ReplicatedStorage",
        script_item(
            "ModuleScript",
            "StoryData",
            os.path.join(src, "ReplicatedStorage", "StoryData.lua"),
        ),
    )

    server_scripts = service_item(
        "ServerScriptService",
        script_item(
            "Script",
            "WorldBuilder",
            os.path.join(src, "ServerScriptService", "WorldBuilder.server.lua"),
        )
        + script_item(
            "Script",
            "StoryServer",
            os.path.join(src, "ServerScriptService", "StoryServer.server.lua"),
        )
        + script_item(
            "Script",
            "AmyOutfit",
            os.path.join(src, "ServerScriptService", "AmyOutfit.server.lua"),
        ),
    )

    starter_player = service_item(
        "StarterPlayer",
        service_item(
            "StarterPlayerScripts",
            script_item(
                "LocalScript",
                "StoryClient",
                os.path.join(
                    src, "StarterPlayer", "StarterPlayerScripts", "StoryClient.client.lua"
                ),
            ),
        ),
    )

    workspace = service_item("Workspace", "")
    lighting = service_item("Lighting", "")

    xml = (
        '<roblox xmlns:xmime="http://schemas.microsoft.com/appx/2006/xmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
        'version="4">\n'
        "<External>null</External>\n"
        "<External>nil</External>\n"
        + workspace
        + lighting
        + replicated
        + server_scripts
        + starter_player
        + "</roblox>\n"
    )

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        f.write(xml)
    print("Wrote %s (%d bytes)" % (OUT_PATH, len(xml)))


if __name__ == "__main__":
    main()
