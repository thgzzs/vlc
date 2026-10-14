/*****************************************************************************
 * Copyright (C) 2021 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * ( at your option ) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/
import QtQuick


import VLC.Widgets as Widgets
import VLC.Style
import VLC.Playlist
import VLC.Util

Widgets.IconToolButton {
    id: prevBtn

    readonly property bool figmaRedesign: Qt.platform.os === "windows" && VLCStyle.palette.isDark
    text: VLCIcons.previous
    contentItem: Item {
        implicitWidth: VLCStyle.dp(24, VLCStyle.scale)
        implicitHeight: VLCStyle.dp(24, VLCStyle.scale)
        Widgets.IconLabel {
            anchors.fill: parent
            text: prevBtn.text
            color: prevBtn.color
            font: prevBtn.font
            visible: !prevBtn.figmaRedesign
        }
        Image {
            anchors.centerIn: parent
            source: "qrc:/figma-redesign/previous.svg"
            sourceSize.width: VLCStyle.dp(24, VLCStyle.scale)
            sourceSize.height: VLCStyle.dp(24, VLCStyle.scale)
            fillMode: Image.PreserveAspectFit
            visible: prevBtn.figmaRedesign
            opacity: prevBtn.enabled ? 1.0 : 0.4
        }
    }
    enabled: MainPlaylistController.hasPrev
    onClicked: MainPlaylistController.prev()
    description: qsTr("Previous")

    AccessibleCompat.id: "previousButton"
}
