#!/usr/bin/env python3
from pathlib import Path
from xml.etree import ElementTree
root=Path(__file__).resolve().parents[1]
qt=root/"modules/gui/qt"
qrc=ElementTree.parse(qt/"assets.qrc")
for name in ("play","pause","previous","next"):
    asset=qt/"pixmaps/figma-redesign"/(name+".svg")
    assert asset.is_file() and asset.stat().st_size>100, asset
    assert ElementTree.parse(asset).getroot().attrib["viewBox"]=="0 0 24 24"
    assert qrc.find(".//file[@alias='"+name+".svg']") is not None
play=(qt/"player/qml/controlbarcontrols/PlayButton.qml").read_text()
assert "MainPlaylistController.togglePlayPause()" in play
assert "figmaPlayIcon" in play
for title,fn in (("PreviousButton.qml","prev()"),("NextButton.qml","next()")):
    t=(qt/"player/qml/controlbarcontrols"/title).read_text()
    assert "MainPlaylistController."+fn in t
print("Figma redesign source checks passed")
