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
#ifndef BULK_SUBTITLE_MATCH_HPP
#define BULK_SUBTITLE_MATCH_HPP
#include <QAbstractListModel>
#include <QStringList>
#include <atomic>
#include <memory>
#include <vector>
#include "qt.hpp"
#include "util/asynctask.hpp"
#include "util/shared_input_item.hpp"
class MediaLib;
class SubtitleMatchScanTask;
class BulkSubtitleMatch : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY changed FINAL)
    Q_PROPERTY(bool canApply READ canApply NOTIFY changed FINAL)
    Q_PROPERTY(QString folder READ folder NOTIFY changed FINAL)
    Q_PROPERTY(QString status READ status NOTIFY changed FINAL)
public:
    BulkSubtitleMatch(qt_intf_t*, MediaLib*, QObject* parent = nullptr);
    ~BulkSubtitleMatch() override;
    enum Roles { MediaName=Qt::UserRole+1, Choices, Selected };
    QHash<int,QByteArray> roleNames() const override;
    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex&, int role) const override;
    bool loading() const { return bool(m_scan) || m_applying; }
    bool canApply() const;
    QString folder() const { return m_folder; }
    QString status() const { return m_status; }
    Q_INVOKABLE void prepare();
    Q_INVOKABLE void chooseFolder();
    Q_INVOKABLE void scan(const QString& path);
    Q_INVOKABLE void select(int row, int choice);
    Q_INVOKABLE void apply();
signals:
    void changed();
private:
    struct Row { uint64_t id; SharedInputItem item; QString uri; QString name; QStringList files; int selected=0; };
    void cancelScan();
    qt_intf_t* const m_intf;
    MediaLib* const m_library;
    QThreadPool m_pool;
    TaskHandle<SubtitleMatchScanTask> m_scan;
    std::shared_ptr<std::atomic_bool> m_cancel;
    std::vector<Row> m_rows;
    QString m_folder;
    QString m_status;
    bool m_applying=false;
};
#endif
