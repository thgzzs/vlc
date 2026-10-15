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
#include "audio_waveform.hpp"
#include "waveform_envelope.hpp"
#include "player/player_controller.hpp"
#include <vlc_player.h>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QDateTime>
#include <QPainter>
#include <QUrl>
#include <algorithm>
#include <vector>

namespace {
constexpr qint64 MaxFileBytes = qint64(2) * 1024 * 1024 * 1024;
constexpr size_t MaxBlockBytes = 1024 * 1024;
QString fileKey(const QString& path, qint64 duration) {
    const QFileInfo info(path);
    return info.canonicalFilePath() + QChar('\n') + QString::number(info.size())
         + QChar('\n') + QString::number(info.lastModified().toMSecsSinceEpoch())
         + QChar('\n') + QString::number(duration);
}
struct Result { QVariantList peaks; QString error; };
}

class AudioWaveformTask : public AsyncTask<Result>
{
public:
    AudioWaveformTask(qt_intf_t* intf, QString path, qint64 duration,
                      std::shared_ptr<std::atomic_bool> cancel)
        : m_intf(intf), m_path(std::move(path)),
          m_cancel(std::move(cancel)), m_envelope(uint64_t(duration)) {}
    Result execute() override {
        if (*m_cancel) return {};
        // Isolate options from the main player, never mutate its input item or
        // persistent defaults. The private object is destroyed after player join.
        auto* object = vlc_object_create<vlc_object_t>(m_intf);
        if (!object) return {{}, AudioWaveform::tr("Could not start audio analysis.")};
        object->no_interact = true;
        var_Create(object, "aout", VLC_VAR_STRING);
        var_SetString(object, "aout", "dummy");
        var_Create(object, "rate", VLC_VAR_FLOAT);
        var_SetFloat(object, "rate", 1.f);
        var_Create(object, "demux-filter", VLC_VAR_STRING);
        var_SetString(object, "demux-filter", "");
        auto* player = vlc_player_New(object, VLC_PLAYER_LOCK_NORMAL);
        if (!player) { vlc_object_delete(object); return {{}, AudioWaveform::tr("Could not start audio analysis.")}; }
        auto* item = input_item_New(qtu(QUrl::fromLocalFile(m_path).toString()), "Waveform analysis");
        static const auto callbacks = [] {
            vlc_player_cbs cbs{};
            cbs.on_state_changed = [](vlc_player_t*, vlc_player_state state, void* data) {
                auto* self = static_cast<AudioWaveformTask*>(data);
                if (state == VLC_PLAYER_STATE_STARTED) self->m_started = true;
                if (state == VLC_PLAYER_STATE_STOPPED && self->m_started) self->m_done = true;
            };
            cbs.on_error_changed = [](vlc_player_t*, vlc_player_error error, void* data) {
                if (error != VLC_PLAYER_ERROR_NONE) {
                    auto* self = static_cast<AudioWaveformTask*>(data);
                    self->m_failed = true; self->m_done = true;
                }
            };
            return cbs;
        }();
        vlc_player_listener_id* listener;
        int started = VLC_EGENERIC;
        {
            vlc_player_locker lock{player};
            listener = vlc_player_AddListener(player, &callbacks, this);
            if (item && listener) {
                const auto output = QStringLiteral("sout=#transcode{acodec=s16l,channels=1,samplerate=8000,threads=1}:smem{time-sync=false,audio-prerender-callback=%1,audio-postrender-callback=%2,audio-data=%3}")
                    .arg(quintptr(&AudioWaveformTask::allocate)).arg(quintptr(&AudioWaveformTask::consume)).arg(quintptr(this));
                input_item_AddOption(item, qtu(output), VLC_INPUT_OPTION_TRUSTED);
                for (const char* option : {"no-video", "no-spu", "sout-audio", "no-sout-video", "no-sout-spu", "no-sout-all", "no-sout-keep", "aout=dummy", "audio-track=0", "audio-filter=", "audio-visual=", "no-start-paused", "start-time=0", "stop-time=0", "run-time=0", "input-repeat=0", "no-metadata-network-access", "sub-autodetect-file=0"})
                    input_item_AddOption(item, option, VLC_INPUT_OPTION_TRUSTED);
                if (vlc_player_SetCurrentMedia(player, item) == VLC_SUCCESS)
                    started = vlc_player_Start(player);
            }
        }
        if (item) input_item_Release(item);
        QElapsedTimer clock; clock.start();
        while (started == VLC_SUCCESS && !m_done && !m_failed && !*m_cancel && clock.elapsed() < 60000)
            QThread::msleep(50);
        const bool timedOut = clock.elapsed() >= 60000;
        {
            vlc_player_locker lock{player};
            vlc_player_Stop(player);
            if (listener) vlc_player_RemoveListener(player, listener);
        }
        // All PCM callbacks are joined before their buffers or parent disappear.
        vlc_player_Delete(player);
        vlc_object_delete(object);
        if (*m_cancel) return {};
        if (timedOut) return {{}, AudioWaveform::tr("Audio analysis exceeded one minute. Try a shorter file.")};
        if (started != VLC_SUCCESS || m_failed || !m_done || !m_frames)
            return {{}, AudioWaveform::tr("Could not decode the primary audio track for its waveform.")};
        QVariantList values; values.reserve(Waveform::BinCount);
        for (float value : m_envelope.peaks()) values.push_back(value);
        return {std::move(values), {}};
    }
private:
    static void allocate(void* data, uint8_t** buffer, size_t size) {
        auto* self = static_cast<AudioWaveformTask*>(data);
        *buffer = nullptr;
        if (*self->m_cancel || size > MaxBlockBytes) { self->m_failed = true; return; }
        try { self->m_buffer.resize(size); *buffer = self->m_buffer.data(); }
        catch (const std::bad_alloc&) { self->m_failed = true; }
    }
    static void consume(void* data, uint8_t* buffer, unsigned channels, unsigned rate,
                        unsigned samples, unsigned bits, size_t size, vlc_tick_t pts) {
        auto* self = static_cast<AudioWaveformTask*>(data);
        if (*self->m_cancel) return;
        if (channels != 1 || rate != Waveform::Rate || bits != 16 || size != size_t(samples) * 2 ||
            self->m_frames + samples > Waveform::Rate * Waveform::MaxSeconds) {
            self->m_failed = true; return;
        }
        // Demuxers may start at a nonzero timestamp. Anchor to the first decoded
        // audio PTS and retain subsequent gaps instead of stretching amplitudes.
        uint64_t firstFrame = self->m_frames;
        if (pts != VLC_TICK_INVALID) {
            if (self->m_firstPts == VLC_TICK_INVALID) self->m_firstPts = pts;
            if (pts >= self->m_firstPts) {
                const uint64_t delta = uint64_t(pts) - uint64_t(self->m_firstPts);
                if (delta > Waveform::MaxSeconds * CLOCK_FREQ) { self->m_failed = true; return; }
                firstFrame = delta * Waveform::Rate / CLOCK_FREQ;
            }
        }
        if (!self->m_envelope.append(buffer, size, firstFrame)) self->m_failed = true;
        self->m_frames += samples;
    }
    qt_intf_t* const m_intf;
    const QString m_path;
    const std::shared_ptr<std::atomic_bool> m_cancel;
    Waveform::Envelope m_envelope;
    std::vector<uint8_t> m_buffer;
    uint64_t m_frames = 0;
    vlc_tick_t m_firstPts = VLC_TICK_INVALID;
    std::atomic_bool m_done{false}, m_failed{false}, m_started{false};
};

AudioWaveform::AudioWaveform(qt_intf_t* intf, QObject* parent)
    : QObject(parent), m_intf(intf) {
    m_pool.setMaxThreadCount(1);
    auto* player = intf->p_mainPlayerController;
    connect(player, &PlayerController::inputChanged, this, &AudioWaveform::refresh);
    connect(player, &PlayerController::lengthChanged, this, &AudioWaveform::refresh);
}
AudioWaveform::~AudioWaveform() { cancel(); m_pool.waitForDone(); }
void AudioWaveform::cancel() {
    if (m_cancel) *m_cancel = true;
    m_task.reset(); m_cancel.reset();
}
double AudioWaveform::peak() const {
    double value = 0;
    for (const auto& bin : m_peaks) value = std::max(value, bin.toDouble());
    return value;
}
QString AudioWaveform::status() const {
    if (loading()) return tr("Analyzing audio…");
    if (!m_error.isEmpty()) return m_error;
    if (!m_peaks.isEmpty()) return tr("Waveform ready, peak %1%").arg(qRound(peak() * 100));
    return tr("Open a local audio or video file to show its waveform.");
}
void AudioWaveform::setEnabled(bool enabled) {
    if (m_enabled == enabled) return;
    m_enabled = enabled; refresh();
}
void AudioWaveform::refresh() {
    QString path;
    const auto duration = m_intf->p_mainPlayerController->getLength().asMilliseconds();
    {
        vlc_player_locker lock{m_intf->p_player};
        auto* item = vlc_player_GetCurrentMedia(m_intf->p_player);
        if (item) {
            const QUrl url(QString::fromUtf8(item->psz_uri));
            if (url.isLocalFile() && url.host().isEmpty()) path = url.toLocalFile();
        }
    }
    const QFileInfo info(path);
    const QString key = m_enabled && !path.isEmpty() && duration > 0 ? fileKey(path, duration) : QString();
    if (!key.isEmpty() && key == m_key && (m_task || !m_peaks.isEmpty())) return;
    cancel(); m_peaks.clear(); m_error.clear(); m_key = key;
    if (!m_enabled || path.isEmpty() || duration <= 0) { emit changed(); return; }
    if (!info.isFile() || info.size() > MaxFileBytes || duration > qint64(Waveform::MaxSeconds * 1000) ||
        path.startsWith(QStringLiteral("//")) || path.startsWith(QStringLiteral("\\\\"))) {
        m_error = tr("Waveforms support local files up to 2 GiB and six hours."); emit changed(); return;
    }
    if (const auto* cached = m_cache.object(key)) {
        msg_Dbg(m_intf, "waveform: cache hit");
        m_peaks = *cached; emit changed(); return;
    }
    m_cancel = std::make_shared<std::atomic_bool>(false);
    m_task.reset(new AudioWaveformTask(m_intf, path, duration, m_cancel));
    connect(m_task.get(), &BaseAsyncTask::result, this, [this, key, path, duration]() {
        auto result = m_task->takeResult(); m_task.reset(); m_cancel.reset();
        if (key != m_key) return;
        if (fileKey(path, duration) != key) {
            m_error = tr("The media file changed during audio analysis. Reopen it to retry.");
        } else {
            m_peaks = std::move(result.peaks); m_error = std::move(result.error);
            if (!m_peaks.isEmpty()) m_cache.insert(key, new QVariantList(m_peaks));
        }
        emit changed();
    });
    m_task->start(m_pool, -1); emit changed();
}

void AudioWaveformView::paint(QPainter* painter) {
    if (m_peaks.isEmpty() || !m_color.isValid()) return;
    const double step = width() / m_peaks.size();
    const auto count = std::min<qsizetype>(m_peaks.size(), Waveform::BinCount);
    for (qsizetype i = 0; i < count; ++i) {
        const double amplitude = std::max(1.0, std::clamp(m_peaks[i].toDouble(), 0.0, 1.0) * height());
        const auto index = m_mirrored ? count - 1 - i : i;
        painter->fillRect(QRectF(index * step, (height() - amplitude)/2,
                                std::max(0.5, step * 0.7), amplitude), m_color);
    }
}
