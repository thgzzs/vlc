/*****************************************************************************
 * Copyright (C) 2023 VLC authors and VideoLAN
 *
 * Authors: Prince Gupta <guptaprince8832@gmail.com>
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
import QtQuick.Templates as T

import VLC.Widgets as Widgets
import VLC.Style
import VLC.Util

T.Slider {
    id: control

    // helper to set colors based on given particular theme
    readonly property ColorContext colorContext: ColorContext {
        id: theme

        colorSet: ColorContext.Slider

        enabled: control.enabled
        focused: control.visualFocus
        hovered: control.hovered
    }

    // colors based on different parts and states
    property color color: VLCStyle.vlcRedesign ? VLCStyle.vlcRedesignAccent : theme.fg.primary
    property color fillColor: VLCStyle.vlcRedesign ? "#3b220a" : color
    property real fillOrigin: from
    readonly property real fillOriginPosition: to === from ? 0 : Math.max(0, Math.min(1, (fillOrigin - from) / (to - from)))

    property color bgColor: VLCStyle.vlcRedesign ? VLCStyle.vlcRedesignBarSurface : theme.bg.primary

    property real handleWidth: VLCStyle.vlcRedesign ? VLCStyle.dp(8, VLCStyle.scale) : VLCStyle.icon_xsmall

    property real radius: VLCStyle.dp(3, VLCStyle.scale)

    // when set the tooltip will follow the mouse when control is hoverred
    // else tooltip will always be shown at current value.
    property bool toolTipFollowsMouse: false

    // toolTipTextProvider -> function(value)
    // arg "value" is between from and to, this is "value"
    // at which pointing tool tip is currently shown
    //
    // returns the text for the given value
    property var toolTipTextProvider: function (value) {
        return value
    }

    readonly property real _tooltipX: {
        if (toolTipFollowsMouse && hoverHandler.hovered)
            return  hoverHandler.point.position.x

        return (handle.x + handle.width / 2) // handle center
    }

    // find position under given x, can be used with Slider::valueAt()
    // x is coordinate in this control's coordinate space
    function positionAt(x) {
        // taken from qt sources QQuickSlider.cpp
        // TODO: support vertical slider
        const hw = control.handle.width
        const offset = control.leftPadding + hw / 2
        const extend = control.availableWidth - hw
        return (x - offset) / extend
    }

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitHandleWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitHandleHeight + topPadding + bottomPadding)

    handle: Rectangle {
        x: control.leftPadding + (control.horizontal
                                  ? control.visualPosition * (control.availableWidth - width)
                                  : (control.availableWidth - width) / 2)

        y: control.topPadding + (control.horizontal
                                 ? (control.availableHeight - height) / 2
                                 : control.visualPosition * (control.availableHeight - height))

        implicitWidth: control.handleWidth
        implicitHeight: implicitWidth

        width: control.handleWidth
        height: VLCStyle.vlcRedesign ? VLCStyle.dp(24, VLCStyle.scale) : width
        radius: VLCStyle.vlcRedesign ? VLCStyle.dp(4, VLCStyle.scale) : width / 2

        color: control.color
        visible: (VLCStyle.vlcRedesign || control.visualFocus || control.pressed) && control.enabled
    }

    background: Rectangle {
        x: control.leftPadding + (control.horizontal ? 0 : (control.availableWidth - width) / 2)
        y: control.topPadding + (control.horizontal ? (control.availableHeight - height) / 2 : 0)

        implicitWidth: control.horizontal ? VLCStyle.heightBar_xlarge : VLCStyle.heightBar_xxsmall
        implicitHeight: control.horizontal ? (VLCStyle.vlcRedesign ? VLCStyle.dp(16, VLCStyle.scale) : VLCStyle.heightBar_xxsmall) : VLCStyle.heightBar_xlarge

        width: control.horizontal ? control.availableWidth : implicitWidth
        height: control.horizontal ? implicitHeight : control.availableHeight

        radius: control.radius

        color: control.bgColor
        scale: control.horizontal && control.mirrored ? -1 : 1

        Rectangle {
            x: control.horizontal ? Math.min(control.position, control.fillOriginPosition) * parent.width : 0
            y: control.horizontal ? 0 : control.visualPosition * parent.height
            width: control.horizontal ? Math.abs(control.position - control.fillOriginPosition) * parent.width : parent.height
            height: control.horizontal ? parent.height : control.position * parent.height

            radius: control.radius
            color: control.fillColor
        }
    }

    HoverHandler {
        id: hoverHandler

        enabled: true

        target: background
    }

    Widgets.PointingToolTipAttached.pos: Qt.point(control._tooltipX, control.handle.height / 2)
    Widgets.PointingToolTipAttached.visible: (hoverHandler.hovered || control.visualFocus || control.pressed)
    Widgets.PointingToolTipAttached.text: {
        if (!Widgets.PointingToolTipAttached.instance?.visible)
            return ""

        // position is only measured till half of handle width
        // pos.x may go beyond the position at the edges
        const p = Helpers.clamp(control.positionAt(Widgets.PointingToolTipAttached.instance.pos.x), 0.0, 1.0)
        const v = control.valueAt(p)
        return control.toolTipTextProvider(v)
    }

}
