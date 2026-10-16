/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
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

// Compact reference toggle: 36x16 face, with a 44x32 pointer/keyboard target.
// Shared by preferences and player panels so their states look alike.
import QtQuick
import QtQuick.Templates as T

import VLC.MainInterface
import VLC.Style

T.AbstractButton {
    id: control

    checkable: true

    implicitWidth: VLCStyle.dp(44)
    implicitHeight: VLCStyle.dp(32)

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.CheckBox
    Accessible.checked: control.checked
    Accessible.checkable: true
    // UI Automation invokes attached actions for this custom CheckBox role.
    // Emit the same clicked signal used by backend setters, after toggling.
    Accessible.onPressAction: control.accessibleToggle()
    Accessible.onToggleAction: control.accessibleToggle()

    function accessibleToggle() {
        if (!control.enabled)
            return
        control.toggle()
        control.clicked()
    }

    Keys.priority: Keys.AfterItem
    Keys.onPressed: (event) => Navigation.defaultKeyAction(event)

    readonly property SystemPalette rdPalette: VLCStyle.palette

    background: Rectangle {
        radius: VLCStyle.rd_radius_small
        color: "transparent"
        border.width: control.visualFocus ? VLCStyle.dp(1) : 0
        border.color: control.rdPalette.rdAccentMain
    }

    contentItem: Item {
        Rectangle {
            width: VLCStyle.dp(36)
            height: VLCStyle.dp(16)
            radius: VLCStyle.dp(2)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: control.checked ? control.rdPalette.rdBgAccentBright : control.rdPalette.rdBgB2

            Rectangle {
                width: VLCStyle.dp(14)
                height: VLCStyle.dp(14)
                radius: VLCStyle.dp(1)
                anchors.verticalCenter: parent.verticalCenter
                x: control.checked ? parent.width - width - VLCStyle.dp(1) : VLCStyle.dp(1)
                color: control.checked ? control.rdPalette.rdAccentDim : control.rdPalette.rdFgA4
            }

            Text {
                width: VLCStyle.dp(20)
                height: parent.height
                x: control.checked ? 0 : parent.width - width
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: control.checked ? qsTr("ON") : qsTr("OFF")
                font.family: VLCStyle.rd_fontFamily
                font.pixelSize: VLCStyle.dp(8)
                // Translated captions stay inside their half of the face.
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: VLCStyle.dp(6)
                color: control.checked ? control.rdPalette.rdAccentMain : control.rdPalette.rdFgA3
                Accessible.ignored: true
            }
        }
    }
}
