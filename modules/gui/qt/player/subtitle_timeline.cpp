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
#include "subtitle_timeline.hpp"
#include "player/player_controller.hpp"
#include <QFile>
#include <QFileInfo>
#include <QStringConverter>
#include <QUrl>
#include <array>
#include <cmath>

struct SubtitleCueResult {
    std::vector<SubtitleCues::Cue> cues;
    QString error;
};
class SubtitleCueTask : public AsyncTask<SubtitleCueResult>
{
public:
    explicit SubtitleCueTask(QString path) : m_path(std::move(path)) {}
    SubtitleCueResult execute() override {
        QFile file(m_path);
        if (!file.open(QIODevice::ReadOnly)) return {{}, file.errorString()};
        if (file.size() > qint64(SubtitleCues::MaxFileBytes))
            return {{}, SubtitleTimeline::tr("Subtitle timeline files must be 8 MiB or smaller.")};
        const auto bytes = file.read(SubtitleCues::MaxFileBytes + 1);
        if (bytes.size() > qsizetype(SubtitleCues::MaxFileBytes))
            return {{}, SubtitleTimeline::tr("Subtitle file exceeded the timeline limit.")};
        const auto encoding = QStringConverter::encodingForData(bytes);
        QStringDecoder decoder(encoding.value_or(QStringConverter::Utf8));
        const auto text = QString(decoder(bytes)).toUtf8();
        if (decoder.hasError())
            return {{}, SubtitleTimeline::tr("Use UTF-8 or Unicode SRT/WebVTT for the cue timeline.")};
        auto cues = SubtitleCues::parse(std::string_view(text.constData(), size_t(text.size())));
        if (cues.empty()) return {{}, SubtitleTimeline::tr("No SRT/WebVTT cues found in this file.")};
        return {std::move(cues), {}};
    }
private:
    const QString m_path;
};

SubtitleTimeline::SubtitleTimeline(qt_intf_t* intf, QObject* parent)
    : QAbstractListModel(parent), m_intf(intf)
{
    auto* player = intf->p_mainPlayerController;
    connect(player, &PlayerController::externalSubtitleFileAdded, this, &SubtitleTimeline::load);
    connect(player, &PlayerController::inputChanged, this, &SubtitleTimeline::clear);
    connect(player, &PlayerController::lengthChanged, this, &SubtitleTimeline::rebuildDensity);
}
SubtitleTimeline::~SubtitleTimeline() = default;
int SubtitleTimeline::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : count();
}
QHash<int, QByteArray> SubtitleTimeline::roleNames() const {
    return {{Start, "startMs"}, {End, "endMs"}, {CueText, "cueText"}, {TimeText, "timeText"}};
}
QVariant SubtitleTimeline::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= count()) return {};
    const auto& cue = m_cues[size_t(index.row())];
    switch (role) {
    case Start: return qlonglong(cue.start);
    case End: return qlonglong(cue.end);
    case CueText: return QString::fromUtf8(cue.text.data(), qsizetype(cue.text.size()));
    case TimeText: return VLCDuration::fromMS(cue.start).formatHMS();
    default: return {};
    }
}
void SubtitleTimeline::clear() {
    m_task.reset();
    beginResetModel(); m_cues.clear(); endResetModel();
    m_uri.clear(); m_fileName.clear(); m_error.clear();
    rebuildDensity(); emit changed();
}
void SubtitleTimeline::load(const QString& uri) {
    const QString requestedUri = uri; // May alias m_uri when enabling a deferred load.
    clear();
    m_uri = requestedUri;
    if (!m_enabled) return;
    const QUrl url(requestedUri);
    if (!url.isLocalFile() || !url.host().isEmpty()) return; // No remote URL fetching.
    const auto path = url.toLocalFile();
    const auto suffix = QFileInfo(path).suffix();
    if (suffix.compare(QStringLiteral("srt"), Qt::CaseInsensitive) &&
        suffix.compare(QStringLiteral("vtt"), Qt::CaseInsensitive)) return;
    m_fileName = QFileInfo(path).fileName();
    m_task.reset(new SubtitleCueTask(path));
    connect(m_task.get(), &BaseAsyncTask::result, this, [this]() {
        auto result = m_task->takeResult();
        m_task.reset();
        beginResetModel(); m_cues = std::move(result.cues); endResetModel();
        m_error = std::move(result.error);
        rebuildDensity(); emit changed();
    });
    m_task->start(*QThreadPool::globalInstance());
    emit changed();
}
void SubtitleTimeline::setEnabled(bool enabled) {
    if (m_enabled == enabled) return;
    m_enabled = enabled;
    if (enabled && m_cues.empty() && !m_uri.isEmpty()) {
        load(m_uri);
    } else {
        if (!enabled && m_task) { m_task.reset(); emit changed(); }
        rebuildDensity();
    }
    emit enabledChanged();
}
void SubtitleTimeline::seek(int row) {
    auto* player = m_intf->p_mainPlayerController;
    if (row < 0 || row >= count() || !player->isSeekable()) return;
    const auto length = player->getLength().asMilliseconds();
    if (length <= 0) return;
    // Source timestamps intentionally remain independent of subtitle FPS/duration effects.
    const auto start = std::clamp<int64_t>(m_cues[size_t(row)].start, 0, length);
    player->setPosition(double(start) / length);
}
void SubtitleTimeline::rebuildDensity() {
    m_density.clear();
    const auto duration = m_intf->p_mainPlayerController->getLength().asMilliseconds();
    if (m_enabled && duration > 0 && !m_cues.empty()) {
        // Fixed 256 bins: bounded scene graph and O(cues + bins) preparation, never per frame.
        std::array<int, 257> changes{};
        for (const auto& cue : m_cues) {
            if (cue.start >= duration) continue;
            const int first = int(std::clamp<int64_t>(cue.start * 256 / duration, 0, 255));
            const int last = int(std::clamp<int64_t>((cue.end * 256 + duration - 1) / duration, first + 1, 256));
            ++changes[size_t(first)]; --changes[size_t(last)];
        }
        int active = 0;
        m_density.reserve(256);
        for (int i = 0; i < 256; ++i) {
            active += changes[size_t(i)]; m_density.push_back(active > 0);
        }
    }
    emit densityChanged();
}
