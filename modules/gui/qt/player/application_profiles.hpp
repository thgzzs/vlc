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
#ifndef APPLICATION_PROFILES_HPP
#define APPLICATION_PROFILES_HPP
#include <QObject>
#include <QStringList>
#include <QVariantMap>
#include "qt.hpp"
class MainCtx;
class RdEffects;

/** Named appearance and playback-default snapshots. Does not mutate toolbar profile IDs. */
class ApplicationProfiles : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList names READ names NOTIFY changed FINAL)
    Q_PROPERTY(QString error READ error NOTIFY changed FINAL)
public:
    ApplicationProfiles(qt_intf_t*, MainCtx*, RdEffects*, QObject* parent = nullptr);
    QStringList names() const;
    QString error() const { return m_error; }
    Q_INVOKABLE bool save(const QString& name);
    Q_INVOKABLE bool apply(const QString& name);
    Q_INVOKABLE bool remove(const QString& name);
signals:
    void changed();
private:
    bool persist(const QVariantMap& records);
    qt_intf_t* const m_intf;
    MainCtx* const m_ctx;
    RdEffects* const m_effects;
    QVariantMap m_records;
    QString m_error;
};
#endif
