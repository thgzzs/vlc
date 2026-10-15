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
#include "seek_preview.hpp"
#include "player/player_controller.hpp"
#include <QCoreApplication>
#include <QFile>
#include <QPointer>
#include <QUuid>
#include <algorithm>
#include <cmath>
#include <memory>
#include <utility>

struct SeekPreview::Context {
    QPointer<SeekPreview> owner;
    quint64 generation;
    qint64 bucket;
    QString path;
    QByteArray pathBytes;
    vlc_thumbnailer_output output{};
};

SeekPreview::SeekPreview(qt_intf_t* intf, QObject* parent)
    : QObject(parent), m_intf(intf)
{
    connect(intf->p_mainPlayerController, &PlayerController::inputChanged, this, &SeekPreview::clear);
}
SeekPreview::~SeekPreview()
{
    cancel();
    if (m_preparser) vlc_preparser_Delete(m_preparser);
}
void SeekPreview::setEnabled(bool enabled)
{
    if (m_enabled == enabled) return;
    m_enabled = enabled;
    if (!enabled) cancel();
    emit enabledChanged();
}
void SeekPreview::cancel()
{
    ++m_generation;
    auto* request = std::exchange(m_request, nullptr);
    m_pendingBucket = -1;
    if (request) {
        vlc_preparser_Cancel(m_preparser, request);
        vlc_preparser_req_Release(request);
    }
    m_imageUrl.clear();
    emit changed();
}
void SeekPreview::clear()
{
    cancel();
    for (const auto& path : std::as_const(m_cache)) QFile::remove(path);
    m_cache.clear(); m_recent.clear(); m_mediaUri.clear(); m_error.clear();
    emit changed();
}
void SeekPreview::requestPreview(double position)
{
    if (!m_enabled || !std::isfinite(position) || !m_directory.isValid()) return;
    auto* player = m_intf->p_mainPlayerController;
    const auto duration = player->getLength().asMilliseconds();
    if (!player->isSeekable() || duration <= 0 || !player->hasVideoOutput()) return;
    const qint64 bucket = qint64(std::min<double>(duration - 1, std::clamp(position, 0.0, 1.0) * duration) / 2000);
    if (m_request && m_pendingBucket == bucket) return;

    input_item_t* item;
    QString uri;
    {
        vlc_player_locker lock{ m_intf->p_player };
        item = vlc_player_GetCurrentMedia(m_intf->p_player);
        if (!item) return;
        uri = QString::fromUtf8(item->psz_uri);
        if (!QUrl(uri).isLocalFile()) return; // Do not start extra network inputs on hover.
        input_item_Hold(item);
    }
    const auto itemHolder = std::unique_ptr<input_item_t, decltype(&input_item_Release)>(item, &input_item_Release);
    if (m_mediaUri != uri) { clear(); m_mediaUri = uri; }
    if (m_cache.contains(bucket)) {
        const auto cachedUrl = QUrl::fromLocalFile(m_cache.value(bucket));
        if (!m_request && m_imageUrl == cachedUrl) return;
        cancel();
        m_recent.removeAll(bucket); m_recent.push_back(bucket);
        m_imageUrl = QUrl::fromLocalFile(m_cache.value(bucket)); m_error.clear();
        emit changed(); return;
    }
    cancel();
    if (!m_preparser) {
        if (vlc_preparser_CheckThumbnailerFormat(VLC_THUMBNAILER_FORMAT_PNG) != VLC_SUCCESS) {
            m_error = tr("Seek previews are unavailable in this build."); emit changed(); return;
        }
        vlc_preparser_cfg cfg{};
        cfg.types = VLC_PREPARSER_TYPE_THUMBNAIL_TO_FILES;
        cfg.max_thumbnailer_threads = 1;
        cfg.timeout = VLC_TICK_FROM_SEC(5);
        cfg.external_process = false;
        m_preparser = vlc_preparser_New(VLC_OBJECT(m_intf), &cfg);
        if (!m_preparser) { m_error = tr("Could not start the preview generator."); emit changed(); return; }
    }
    auto context = std::make_unique<Context>();
    context->owner = this; context->generation = m_generation; context->bucket = bucket;
    context->path = m_directory.filePath(QUuid::createUuid().toString(QUuid::WithoutBraces) + QStringLiteral(".png"));
    context->pathBytes = context->path.toUtf8();
    context->output.format = VLC_THUMBNAILER_FORMAT_PNG;
    context->output.width = 320; context->output.height = 180;
    context->output.crop = false;
    context->output.file_path = context->pathBytes.constData();
    context->output.creat_mode = 0600;
    vlc_thumbnailer_arg args{};
    args.seek.type = decltype(args.seek)::VLC_THUMBNAILER_SEEK_TIME;
    args.seek.time = VLC_TICK_FROM_MS(qint64(bucket) * 2000);
    args.seek.speed = decltype(args.seek)::VLC_THUMBNAILER_SEEK_FAST;
    static const vlc_thumbnailer_to_files_cbs callbacks{ &SeekPreview::ended };
    m_request = vlc_preparser_req_NewThumbnailToFiles(m_preparser, item, &args,
                                                    &context->output, 1, &callbacks, context.get());
    if (!m_request) { m_error = tr("Could not create a seek preview."); emit changed(); return; }
    m_pendingBucket = bucket;
    if (vlc_preparser_Submit(m_preparser, m_request) != VLC_SUCCESS) {
        vlc_preparser_req_Release(m_request); m_request = nullptr; m_pendingBucket = -1;
        m_error = tr("Could not queue a seek preview."); emit changed(); return;
    }
    // Submit may invoke the callback synchronously. It queues completion on the UI thread.
    context.release(); m_error.clear(); emit changed();
}
void SeekPreview::ended(vlc_preparser_req*, int status, const bool* results, size_t count, void* data)
{
    const auto context = std::unique_ptr<Context>(static_cast<Context*>(data));
    const bool success = status == VLC_SUCCESS && count == 1 && results && results[0];
    // Inspect the guarded owner only on its UI thread. Preparser destruction joins callbacks.
    QMetaObject::invokeMethod(QCoreApplication::instance(),
        [owner = context->owner, generation = context->generation,
         bucket = context->bucket, path = context->path, success]() {
            if (owner) owner->completed(generation, bucket, path, success);
            else QFile::remove(path);
        }, Qt::QueuedConnection);
}
void SeekPreview::completed(quint64 generation, qint64 bucket, const QString& path, bool success)
{
    if (generation != m_generation) { QFile::remove(path); return; }
    if (m_request) { vlc_preparser_req_Release(m_request); m_request = nullptr; }
    m_pendingBucket = -1;
    if (!success) {
        QFile::remove(path); m_imageUrl.clear(); m_error = tr("Preview unavailable for this position.");
    } else {
        m_cache.insert(bucket, path); m_recent.push_back(bucket);
        while (m_recent.size() > 32) QFile::remove(m_cache.take(m_recent.takeFirst()));
        m_imageUrl = QUrl::fromLocalFile(path); m_error.clear();
    }
    emit changed();
}
