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
#include "folder_presets.hpp"
#include "player/player_controller.hpp"
#include <QDir>
#include <QFileInfo>
#include <QSettings>
#include <QUrl>
#include <cmath>

namespace {
const QString storage=QStringLiteral("Redesign/FolderTimingPresetsV1");
QString folderFor(input_item_t* item) {
    if(!item) return {};
    const QUrl url(QString::fromUtf8(item->psz_uri));
    const auto path=url.toLocalFile();
    if(!url.isLocalFile()||!url.host().isEmpty()||path.startsWith(QStringLiteral("//"))||path.startsWith(QStringLiteral("\\\\"))) return {};
    return QFileInfo(QFileInfo(path).absolutePath()).canonicalFilePath();
}
}
FolderPresets::FolderPresets(qt_intf_t* intf,QObject* parent):QObject(parent),m_intf(intf) {
    m_records=intf->mainSettings->value(storage).toMap();
    if(m_records.size()>128) m_records.clear();
    connect(intf->p_mainPlayerController,&PlayerController::inputChanged,this,[this]{++m_revision;refresh();});
    connect(intf->p_mainPlayerController,&PlayerController::playingStateChanged,this,&FolderPresets::refresh);
    refresh();
}
QString FolderPresets::folderName() const { return QFileInfo(m_folder).fileName(); }
FolderPresets::Timing FolderPresets::read() const {
    return {vlc_player_GetRate(m_intf->p_player),vlc_player_GetAssociatedSubsFPS(m_intf->p_player),
            MS_FROM_VLC_TICK(vlc_player_GetAudioDelay(m_intf->p_player)),
            MS_FROM_VLC_TICK(vlc_player_GetSubtitleDelay(m_intf->p_player))};
}
void FolderPresets::applyTiming(const Timing& values) {
    if(vlc_player_CanChangeRate(m_intf->p_player)) vlc_player_ChangeRate(m_intf->p_player,float(values.rate));
    vlc_player_SetAssociatedSubsFPS(m_intf->p_player,float(values.fps));
    vlc_player_SetAudioDelay(m_intf->p_player,VLC_TICK_FROM_MS(values.audio),VLC_PLAYER_WHENCE_ABSOLUTE);
    vlc_player_SetSubtitleDelay(m_intf->p_player,VLC_TICK_FROM_MS(values.subtitle),VLC_PLAYER_WHENCE_ABSOLUTE);
}
void FolderPresets::restore(bool delays) {
    if(!m_overridden) return;
    vlc_player_ChangeRate(m_intf->p_player,float(m_entry.rate));
    vlc_player_SetAssociatedSubsFPS(m_intf->p_player,float(m_entry.fps));
    if(delays) {
        vlc_player_SetAudioDelay(m_intf->p_player,VLC_TICK_FROM_MS(m_entry.audio),VLC_PLAYER_WHENCE_ABSOLUTE);
        vlc_player_SetSubtitleDelay(m_intf->p_player,VLC_TICK_FROM_MS(m_entry.subtitle),VLC_PLAYER_WHENCE_ABSOLUTE);
    }
    m_overridden=false;
}
bool FolderPresets::valid(const QVariantMap& record,Timing& values) const {
    const auto name=record.value(QStringLiteral("name")).toString();
    if(record.value(QStringLiteral("version")).toInt()!=1||name.isEmpty()||name.size()>80||name.contains(QChar::Null)) return false;
    values={record.value(QStringLiteral("rate"),1).toDouble(),record.value(QStringLiteral("fps"),0).toDouble(),
            record.value(QStringLiteral("audioMs"),0).toLongLong(),record.value(QStringLiteral("subtitleMs"),0).toLongLong()};
    return std::isfinite(values.rate)&&values.rate>=0.25&&values.rate<=4&&std::isfinite(values.fps)&&values.fps>=0&&values.fps<=120&&
           values.audio>=-600000&&values.audio<=600000&&values.subtitle>=-600000&&values.subtitle<=600000;
}
void FolderPresets::refresh() {
    {
        vlc_player_locker lock{m_intf->p_player};
        auto* item=vlc_player_GetCurrentMedia(m_intf->p_player);
        const auto state=vlc_player_GetState(m_intf->p_player);
        m_ready=state==VLC_PLAYER_STATE_PLAYING||state==VLC_PLAYER_STATE_PAUSED;
        m_folder=folderFor(item);
        if(!m_ready) {
            if(state==VLC_PLAYER_STATE_STOPPED) {restore(false);m_seen.reset();}
        } else if(m_seen.get()!=item||m_seenRevision!=m_revision) {
            // Rate/FPS live on the player. Restore those before snapshotting the
            // next input; category delays already belong to the new input.
            auto entry=read();
            if(m_overridden) { entry.rate=m_entry.rate;entry.fps=m_entry.fps; }
            restore(false);
            m_entry=entry;m_seen.reset(item?input_item_Hold(item):nullptr);m_seenRevision=m_revision;
            Timing values;
            if(!m_folder.isEmpty()&&valid(m_records.value(m_folder).toMap(),values)) {
                applyTiming(values);m_overridden=true;
            }
        }
    }
    if(m_folder.isEmpty()) m_status=tr("Open a local show episode to save timing for its folder.");
    else if(m_overridden) m_status=tr("Timing preset applied: %1").arg(m_records.value(m_folder).toMap().value(QStringLiteral("name")).toString());
    else m_status=hasPreset()?tr("Timing preset saved for this folder."):tr("No timing preset for this folder.");
    emit changed();
}
bool FolderPresets::persist(const QVariantMap& records) {
    m_intf->mainSettings->setValue(storage,records);m_intf->mainSettings->sync();
    if(m_intf->mainSettings->status()!=QSettings::NoError) {m_status=tr("Could not save folder timing presets.");emit changed();return false;}
    m_records=records;return true;
}
bool FolderPresets::save(const QString& requestedName) {
    const auto name=requestedName.trimmed();
    if(name.isEmpty()||name.size()>80||name.contains(QChar::Null)||!canSave()) {m_status=tr("Enter a preset name of 1 to 80 characters while playing a local file.");emit changed();return false;}
    if(!hasPreset()&&m_records.size()>=128) {m_status=tr("Up to 128 show folders can have timing presets.");emit changed();return false;}
    Timing values;
    {
        vlc_player_locker lock{m_intf->p_player};
        if(folderFor(vlc_player_GetCurrentMedia(m_intf->p_player))!=m_folder) return false;
        values=read();
    }
    QVariantMap record{{QStringLiteral("version"),1},{QStringLiteral("name"),name},{QStringLiteral("rate"),values.rate},
        {QStringLiteral("fps"),values.fps},{QStringLiteral("audioMs"),values.audio},{QStringLiteral("subtitleMs"),values.subtitle}};
    if(!valid(record,values)) {m_status=tr("Use speed 0.25–4×, subtitle FPS 0–120 and delays within ten minutes.");emit changed();return false;}
    auto records=m_records;records.insert(m_folder,record);
    if(!persist(records)) return false;
    m_overridden=true;m_status=tr("Timing preset applied: %1").arg(name);emit changed();return true;
}
bool FolderPresets::remove() {
    if(!hasPreset()) return false;
    auto records=m_records;records.remove(m_folder);
    if(!persist(records)) return false;
    {
        vlc_player_locker lock{m_intf->p_player};
        restore(m_seen.get()==vlc_player_GetCurrentMedia(m_intf->p_player));
    }
    m_status=tr("Timing preset removed; previous timing restored.");emit changed();return true;
}
