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
#ifndef AUDIO_WAVEFORM_HPP
#define AUDIO_WAVEFORM_HPP
#include <QObject>
#include <QCache>
#include <QQuickPaintedItem>
#include <QColor>
#include <QThreadPool>
#include <QVariantList>
#include <atomic>
#include <memory>
#include "qt.hpp"
#include "util/asynctask.hpp"
class AudioWaveformTask;

/** Optional, bounded analysis of the primary audio track of local media. */
class AudioWaveform : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY changed FINAL)
    Q_PROPERTY(bool loading READ loading NOTIFY changed FINAL)
    Q_PROPERTY(QVariantList peaks READ peaks NOTIFY changed FINAL)
    Q_PROPERTY(QString status READ status NOTIFY changed FINAL)
    Q_PROPERTY(double peak READ peak NOTIFY changed FINAL)
public:
    explicit AudioWaveform(qt_intf_t*, QObject* parent = nullptr);
    ~AudioWaveform() override;
    bool enabled() const { return m_enabled; }
    bool loading() const { return bool(m_task); }
    QVariantList peaks() const { return m_peaks; }
    double peak() const;
    QString status() const;
    void setEnabled(bool enabled);
signals:
    void changed();
private:
    void refresh();
    void cancel();
    qt_intf_t* const m_intf;
    QThreadPool m_pool;
    TaskHandle<AudioWaveformTask> m_task;
    std::shared_ptr<std::atomic_bool> m_cancel;
    QCache<QString, QVariantList> m_cache{32};
    QVariantList m_peaks;
    QString m_key;
    QString m_error;
    bool m_enabled = false;
};
/** One cached texture; repaint only for data/theme/geometry changes. */
class AudioWaveformView : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QVariantList peaks READ peaks WRITE setPeaks NOTIFY peaksChanged FINAL)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged FINAL)
    Q_PROPERTY(bool mirrored READ mirrored WRITE setMirrored NOTIFY mirroredChanged FINAL)
public:
    explicit AudioWaveformView(QQuickItem* parent = nullptr) : QQuickPaintedItem(parent) {}
    QVariantList peaks() const { return m_peaks; }
    QColor color() const { return m_color; }
    bool mirrored() const { return m_mirrored; }
    void setPeaks(const QVariantList& peaks) { m_peaks = peaks; update(); emit peaksChanged(); }
    void setColor(const QColor& color) { if (m_color == color) return; m_color = color; update(); emit colorChanged(); }
    void setMirrored(bool mirrored) { if (m_mirrored == mirrored) return; m_mirrored = mirrored; update(); emit mirroredChanged(); }
    void paint(QPainter*) override;
signals:
    void peaksChanged();
    void colorChanged();
    void mirroredChanged();
private:
    QVariantList m_peaks;
    QColor m_color;
    bool m_mirrored = false;
};
#endif
