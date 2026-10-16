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
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#include "playback_tools.hpp"
#include "player/player_controller.hpp"
#include "playlist/playlist_controller.hpp"
#include <algorithm>

PlaybackTools::PlaybackTools(qt_intf_t* intf, QObject* parent)
    : QObject(parent), m_intf(intf)
{
    m_sleepTimer.setInterval(1000);
    connect(&m_sleepTimer, &QTimer::timeout, this, &PlaybackTools::updateSleep);
    connect(intf->p_mainPlayerController, &PlayerController::inputChanged, this, [this]() {
        if (!m_statistics.isEmpty()) {
            m_statistics.clear();
            emit statisticsChanged();
        }
    });
}

void PlaybackTools::setSleepMinutes(int minutes)
{
    minutes = std::clamp(minutes, 0, 24 * 60);
    msg_Dbg(m_intf, "sleep timer: requested %d minute(s)", minutes);
    if (minutes == 0) {
        m_sleepTimer.stop();
        if (m_sleepRemaining == 0)
            return;
        m_sleepRemaining = 0;
        emit sleepChanged();
        return;
    }
    m_sleepDeadline = QDeadlineTimer(qint64(minutes) * 60000, Qt::PreciseTimer);
    m_sleepRemaining = minutes * 60;
    m_sleepTimer.start();
    msg_Dbg(m_intf, "sleep timer: armed for %d minute(s)", minutes);
    emit sleepChanged();
}

void PlaybackTools::updateSleep()
{
    // QDeadlineTimer uses a monotonic clock: system date/time edits cannot extend a timer.
    const auto remaining = m_sleepDeadline.remainingTime();
    const int seconds = int((remaining + 999) / 1000);
    if (m_sleepRemaining != seconds) {
        m_sleepRemaining = seconds;
        emit sleepChanged();
    }
    if (remaining == 0) {
        m_sleepTimer.stop();
        msg_Dbg(m_intf, "sleep timer: deadline reached; stopping playback");
        m_intf->p_mainPlaylistController->stop();
        emit sleepExpired();
    }
}

void PlaybackTools::setStatisticsEnabled(bool enabled)
{
    if (m_statisticsEnabled == enabled)
        return;
    m_statisticsEnabled = enabled;
    if (enabled) {
        m_statisticsConnection = connect(m_intf->p_mainPlayerController,
            &PlayerController::statisticsUpdated, this, [this](const input_stats_t& s) {
                m_statistics = {
                    {QStringLiteral("readBytes"), QVariant::fromValue<qulonglong>(s.i_read_bytes)},
                    {QStringLiteral("inputKbps"), s.f_input_bitrate * 8000.0},
                    {QStringLiteral("demuxKbps"), s.f_demux_bitrate * 8000.0},
                    {QStringLiteral("decodedVideo"), QVariant::fromValue<qulonglong>(s.i_decoded_video)},
                    {QStringLiteral("decodedAudio"), QVariant::fromValue<qulonglong>(s.i_decoded_audio)},
                    {QStringLiteral("displayedFrames"), QVariant::fromValue<qulonglong>(s.i_displayed_pictures)},
                    {QStringLiteral("lostFrames"), QVariant::fromValue<qulonglong>(s.i_lost_pictures)},
                    {QStringLiteral("lostAudioBuffers"), QVariant::fromValue<qulonglong>(s.i_lost_abuffers)}
                };
                emit statisticsChanged();
            });
    } else {
        disconnect(m_statisticsConnection);
        m_statistics.clear();
        emit statisticsChanged();
    }
    emit statisticsEnabledChanged();
}
