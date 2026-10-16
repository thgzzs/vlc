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
#ifndef FOLDER_PRESETS_HPP
#define FOLDER_PRESETS_HPP
#include <QObject>
#include <QVariantMap>
#include "qt.hpp"
#include "util/shared_input_item.hpp"
/** Per-folder timing only; never writes VLC's global configuration. */
class FolderPresets : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString folderName READ folderName NOTIFY changed FINAL)
    Q_PROPERTY(QString status READ status NOTIFY changed FINAL)
    Q_PROPERTY(bool canSave READ canSave NOTIFY changed FINAL)
    Q_PROPERTY(bool hasPreset READ hasPreset NOTIFY changed FINAL)
public:
    explicit FolderPresets(qt_intf_t*,QObject* parent=nullptr);
    QString folderName() const;
    QString status() const { return m_status; }
    bool canSave() const { return !m_folder.isEmpty()&&m_ready; }
    bool hasPreset() const { return m_records.contains(m_folder); }
    Q_INVOKABLE bool save(const QString& name);
    Q_INVOKABLE bool remove();
signals:
    void changed();
private:
    struct Timing { double rate=1; double fps=0; qint64 audio=0; qint64 subtitle=0; };
    Timing read() const;
    void applyTiming(const Timing&);
    void restore(bool delays);
    void refresh();
    bool persist(const QVariantMap&);
    bool valid(const QVariantMap&,Timing&) const;
    qt_intf_t* const m_intf;
    QVariantMap m_records;
    QString m_folder,m_status;
    SharedInputItem m_seen;
    Timing m_entry;
    quint64 m_revision=0,m_seenRevision=0;
    bool m_overridden=false,m_ready=false;
};
#endif
