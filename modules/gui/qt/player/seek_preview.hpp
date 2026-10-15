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
#ifndef SEEK_PREVIEW_HPP
#define SEEK_PREVIEW_HPP
#include <QObject>
#include <QMap>
#include <QList>
#include <QTemporaryDir>
#include <QUrl>
#include "qt.hpp"
#include <vlc_preparser.h>

/** Local-video seek previews using VLC's thumbnailer, with a single cancellable request. */
class SeekPreview : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged FINAL)
    Q_PROPERTY(QUrl imageUrl READ imageUrl NOTIFY changed FINAL)
    Q_PROPERTY(bool loading READ loading NOTIFY changed FINAL)
    Q_PROPERTY(QString error READ error NOTIFY changed FINAL)
public:
    explicit SeekPreview(qt_intf_t* intf, QObject* parent = nullptr);
    ~SeekPreview() override;
    bool enabled() const { return m_enabled; }
    void setEnabled(bool enabled);
    QUrl imageUrl() const { return m_imageUrl; }
    bool loading() const { return m_request != nullptr; }
    QString error() const { return m_error; }
    Q_INVOKABLE void requestPreview(double position);
    Q_INVOKABLE void cancel();
signals:
    void enabledChanged();
    void changed();
private:
    struct Context;
    static void ended(vlc_preparser_req*, int, const bool*, size_t, void*);
    void completed(quint64 generation, qint64 bucket, const QString& path, bool success);
    void clear();
    qt_intf_t* const m_intf;
    vlc_preparser_t* m_preparser = nullptr;
    vlc_preparser_req* m_request = nullptr;
    QTemporaryDir m_directory;
    QMap<qint64, QString> m_cache;
    QList<qint64> m_recent;
    QString m_mediaUri;
    QUrl m_imageUrl;
    QString m_error;
    quint64 m_generation = 0;
    qint64 m_pendingBucket = -1;
    bool m_enabled = true;
};
#endif
