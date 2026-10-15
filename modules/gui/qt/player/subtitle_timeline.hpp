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
#ifndef SUBTITLE_TIMELINE_HPP
#define SUBTITLE_TIMELINE_HPP
#include <QAbstractListModel>
#include <QVariantList>
#include "qt.hpp"
#include "subtitle_cues.hpp"
#include "util/asynctask.hpp"
class SubtitleCueTask;

class SubtitleTimeline : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY changed FINAL)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged FINAL)
    Q_PROPERTY(bool loading READ loading NOTIFY changed FINAL)
    Q_PROPERTY(QString fileName READ fileName NOTIFY changed FINAL)
    Q_PROPERTY(QString error READ error NOTIFY changed FINAL)
    Q_PROPERTY(QVariantList density READ density NOTIFY densityChanged FINAL)
public:
    explicit SubtitleTimeline(qt_intf_t* intf, QObject* parent = nullptr);
    ~SubtitleTimeline() override;
    enum Roles { Start = Qt::UserRole + 1, End, CueText, TimeText };
    QHash<int, QByteArray> roleNames() const override;
    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    int count() const { return int(m_cues.size()); }
    bool enabled() const { return m_enabled; }
    void setEnabled(bool enabled);
    bool loading() const { return bool(m_task); }
    QString fileName() const { return m_fileName; }
    QString error() const { return m_error; }
    QVariantList density() const { return m_density; }
    Q_INVOKABLE void seek(int row);
private:
    void load(const QString& uri);
    void clear();
    void rebuildDensity();
    qt_intf_t* const m_intf;
    TaskHandle<SubtitleCueTask> m_task;
    std::vector<SubtitleCues::Cue> m_cues;
    QString m_uri;
    QString m_fileName;
    QString m_error;
    QVariantList m_density;
    bool m_enabled = false;
};
#endif
