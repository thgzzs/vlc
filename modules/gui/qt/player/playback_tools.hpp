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
#ifndef PLAYBACK_TOOLS_HPP
#define PLAYBACK_TOOLS_HPP

#include <QObject>
#include <QDeadlineTimer>
#include <QTimer>
#include <QVariantMap>
#include "qt.hpp"

/** Small, demand-driven playback services. No decoder or extra input polling. */
class PlaybackTools : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int sleepRemainingSeconds READ sleepRemainingSeconds NOTIFY sleepChanged FINAL)
    Q_PROPERTY(bool statisticsEnabled READ statisticsEnabled WRITE setStatisticsEnabled NOTIFY statisticsEnabledChanged FINAL)
    Q_PROPERTY(QVariantMap statistics READ statistics NOTIFY statisticsChanged FINAL)
public:
    explicit PlaybackTools(qt_intf_t* intf, QObject* parent = nullptr);
    int sleepRemainingSeconds() const { return m_sleepRemaining; }
    bool statisticsEnabled() const { return m_statisticsEnabled; }
    QVariantMap statistics() const { return m_statistics; }
    void setStatisticsEnabled(bool enabled);
    // Wall-clock duration, including paused playback. Zero cancels; maximum one day.
    Q_INVOKABLE void setSleepMinutes(int minutes);

signals:
    void sleepChanged();
    void sleepExpired();
    void statisticsEnabledChanged();
    void statisticsChanged();

private:
    void updateSleep();
    qt_intf_t* const m_intf;
    QDeadlineTimer m_sleepDeadline;
    QTimer m_sleepTimer;
    int m_sleepRemaining = 0;
    bool m_statisticsEnabled = false;
    QVariantMap m_statistics;
    QMetaObject::Connection m_statisticsConnection;
};
#endif
