"""Packs the Ice Beam scripts into IceBeam/IceBeam.rbxmx, a Tool you can insert into StarterPack."""
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent / "IceBeam"


def script_item(cls, ref, name, source_file):
    source = (ROOT / source_file).read_text()
    if "]]>" in source:
        raise ValueError(f"{source_file} contains ']]>' and can't go in a CDATA block")
    return f"""    <Item class="{cls}" referent="{ref}">
      <Properties>
        <string name="Name">{escape(name)}</string>
        <ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString>
      </Properties>
    </Item>
"""


xml = f"""<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
  <External>null</External>
  <External>nil</External>
  <Item class="Tool" referent="RBX0">
    <Properties>
      <string name="Name">IceBeam</string>
      <string name="ToolTip">Ice Beam</string>
      <bool name="RequiresHandle">false</bool>
      <bool name="CanBeDropped">false</bool>
    </Properties>
    <Item class="RemoteEvent" referent="RBX1">
      <Properties>
        <string name="Name">FireBeam</string>
      </Properties>
    </Item>
{script_item("Script", "RBX2", "IceBeamServer", "IceBeamServer.server.lua")}{script_item("LocalScript", "RBX3", "IceBeamClient", "IceBeamClient.client.lua")}  </Item>
</roblox>
"""

(ROOT / "IceBeam.rbxmx").write_text(xml)
print(f"Wrote {ROOT / 'IceBeam.rbxmx'}")
