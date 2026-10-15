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

// Native playback services and live information, following the reference sidebar.
import QtQuick
import QtQuick.Layouts

import VLC.MainInterface
import VLC.Style
import VLC.Player
import VLC.Dialogs
import VLC.Widgets as Widgets

RdSidePanelPage {
    id: root

    key: "playback"
    property bool showMetadata: false
    property bool showStatistics: false
    property int sleepMinutes: 30

    // Listening and allocating statistics only while the expanded section is visible.
    Binding {
        target: PlaybackTools
        property: "statisticsEnabled"
        value: root.active && root.visible && root.showStatistics
    }

    function countdown(seconds) {
        return Math.floor(seconds / 60) + ":" + (seconds % 60).toString().padStart(2, "0")
    }

    component InfoRow: Widgets.RdSettingRow {
        id: infoRow
        property string value: ""
        Text {
            width: VLCStyle.dp(190)
            text: infoRow.value
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignRight
            font.family: VLCStyle.rd_fontFamily
            font.pixelSize: VLCStyle.rd_fontSize_label
            color: VLCStyle.palette.rdFgA1
            Accessible.name: text
        }
    }

    Widgets.RdSettingsSection {
        showDivider: false
        Widgets.RdSettingRow {
            text: qsTr("Show Subtitle Timeline")
            Widgets.RdToggle {
                checked: SubtitleTimeline.enabled
                Accessible.name: qsTr("Show Subtitle Timeline")
                onClicked: SubtitleTimeline.enabled = checked
            }
        }
        Widgets.RdSettingRow {
            text: qsTr("Show Metadata")
            Widgets.RdToggle {
                checked: root.showMetadata
                Accessible.name: qsTr("Show Metadata")
                onClicked: root.showMetadata = checked
            }
        }
        ColumnLayout {
            visible: root.showMetadata
            Layout.fillWidth: true
            spacing: 0
            InfoRow { text: qsTr("Title"); value: Player.title || Player.name || qsTr("No media") }
            InfoRow { text: qsTr("Artist"); value: Player.artist || qsTr("Unknown") }
            InfoRow { text: qsTr("Album"); value: Player.album || qsTr("Unknown") }
            InfoRow { text: qsTr("Source"); value: String(Player.url) }
            Widgets.RdButton {
                text: qsTr("Edit Media Information")
                Layout.fillWidth: true
                onClicked: DialogsProvider.mediaInfoDialog()
            }
        }
        Widgets.RdSettingRow {
            text: qsTr("Show Statistics")
            Widgets.RdToggle {
                checked: root.showStatistics
                Accessible.name: qsTr("Show Statistics")
                onClicked: root.showStatistics = checked
            }
        }
        ColumnLayout {
            visible: root.showStatistics
            Layout.fillWidth: true
            spacing: 0
            InfoRow { text: qsTr("Input bitrate"); value: qsTr("%1 kb/s").arg(Number(PlaybackTools.statistics.inputKbps ?? 0).toFixed(1)) }
            InfoRow { text: qsTr("Stream bitrate"); value: qsTr("%1 kb/s").arg(Number(PlaybackTools.statistics.demuxKbps ?? 0).toFixed(1)) }
            InfoRow { text: qsTr("Data read"); value: qsTr("%1 MiB").arg(Number((PlaybackTools.statistics.readBytes ?? 0) / 1048576).toFixed(2)) }
            InfoRow { text: qsTr("Decoded video"); value: String(PlaybackTools.statistics.decodedVideo ?? 0) }
            InfoRow { text: qsTr("Decoded audio"); value: String(PlaybackTools.statistics.decodedAudio ?? 0) }
            InfoRow { text: qsTr("Displayed frames"); value: String(PlaybackTools.statistics.displayedFrames ?? 0) }
            InfoRow { text: qsTr("Lost frames"); value: String(PlaybackTools.statistics.lostFrames ?? 0) }
            InfoRow { text: qsTr("Lost audio buffers"); value: String(PlaybackTools.statistics.lostAudioBuffers ?? 0) }
            Widgets.RdButton {
                text: qsTr("Codec Information")
                Layout.fillWidth: true
                onClicked: DialogsProvider.mediaCodecDialog()
            }
        }
    }

    Widgets.RdSettingsSection {
        title: qsTr("Sleep Timer")
        note: qsTr("Stops playback when the countdown ends, including time spent paused.")
        Widgets.RdSettingRow {
            text: PlaybackTools.sleepRemainingSeconds > 0
                ? root.countdown(PlaybackTools.sleepRemainingSeconds) : qsTr("Sleep Timer")
            Widgets.RdToggle {
                checked: PlaybackTools.sleepRemainingSeconds > 0
                Accessible.name: qsTr("Sleep Timer")
                onClicked: PlaybackTools.setSleepMinutes(checked ? root.sleepMinutes : 0)
            }
        }
        Widgets.RdSettingRow {
            text: qsTr("Minutes")
            Widgets.RdValueBox {
                text: String(root.sleepMinutes)
                Accessible.name: qsTr("Sleep Timer Minutes")
                onEdited: (text) => {
                    const minutes = Number(text)
                    if (!Number.isFinite(minutes) || minutes < 1 || minutes > 1440)
                        return
                    root.sleepMinutes = Math.floor(minutes)
                    if (PlaybackTools.sleepRemainingSeconds > 0)
                        PlaybackTools.setSleepMinutes(root.sleepMinutes)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: VLCStyle.dp(8)
            Repeater {
                model: [30, 60, 90]
                Widgets.RdButton {
                    required property int modelData
                    Layout.fillWidth: true
                    implicitWidth: 0
                    text: qsTr("%1 min").arg(modelData)
                    onClicked: {
                        root.sleepMinutes = modelData
                        PlaybackTools.setSleepMinutes(modelData)
                    }
                }
            }
        }
    }

    function rateText(rate) {
        return qsTr("%1x").arg(Math.round(rate * 100) / 100)
    }

    Widgets.RdSettingsSection {
        showDivider: false

        Widgets.RdSettingRow {
            text: qsTr("Audio Visualizer")
            rowHeight: VLCStyle.dp(58)

            Widgets.RdChoiceDropdown {
                implicitWidth: VLCStyle.dp(220)
                choices: Player.audioVisualization
                Accessible.name: qsTr("Audio Visualizer")
            }
        }

        // the video's speed slider: 0.25 to 2 in 0.25 steps with a label under each step;
        // the value box also takes VLC's other speeds (up to 4x)
        Widgets.RdParamSlider {
            text: qsTr("Speed")
            valueBox: true
            valueText: root.rateText(Player.rate)
            from: 0.25
            to: 2
            stepSize: 0.25
            labels: ["0.25", "0.5", "0.75", "1", "1.25", "1.5", "1.75", "2"]
            value: Player.rate
            enabled: Player.ratechangable
            onMoved: (v) => Player.rate = v
            onEdited: (text) => {
                const r = parseFloat(String(text).replace(",", ".").replace(/[^0-9.]/g, ""))
                if (!isNaN(r))
                    Player.rate = Math.max(0.25, Math.min(4, r))
            }
        }
    }
}
