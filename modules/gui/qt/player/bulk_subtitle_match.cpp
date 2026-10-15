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
#include "bulk_subtitle_match.hpp"
#include "subtitle_match.hpp"
#include "dialogs/dialogs_provider.hpp"
#include "medialibrary/medialib.hpp"
#include "medialibrary/mlhelper.hpp"
#include <QDirIterator>
#include <QFileInfo>
#include <QHash>
#include <QUrl>
#include <vlc_playlist.h>

namespace {
constexpr int MaxQueue=200, MaxFiles=5000, MaxCandidates=32;
QString normalise(const QString& stem) {
    const auto bytes=stem.normalized(QString::NormalizationForm_KC).toCaseFolded().toUtf8();
    return QString::fromUtf8(SubtitleMatch::normalise(std::string_view(bytes.constData(),size_t(bytes.size()))));
}
bool localPath(const QString& path) {
    return !path.isEmpty() && !path.startsWith(QStringLiteral("//")) && !path.startsWith(QStringLiteral("\\\\"));
}
struct ScanResult { QHash<QString,QStringList> matches; QString error; };
}
class SubtitleMatchScanTask : public AsyncTask<ScanResult> {
public:
    SubtitleMatchScanTask(QString path,std::shared_ptr<std::atomic_bool> cancel): m_path(std::move(path)),m_cancel(std::move(cancel)) {}
    ScanResult execute() override {
        ScanResult result;
        QDirIterator iterator(m_path,QDir::AllEntries|QDir::NoSymLinks|QDir::NoDotAndDotDot);
        int visited=0;
        while(iterator.hasNext()) {
            if(*m_cancel) return {};
            iterator.next();
            if (++visited>MaxFiles) return {{},BulkSubtitleMatch::tr("Choose a folder with at most 5,000 entries.")};
            const auto info=iterator.fileInfo();
            if(!info.isFile()) continue;
            const auto ext=info.suffix().toLower();
            if (!QStringList{QStringLiteral("srt"),QStringLiteral("vtt"),QStringLiteral("ass"),QStringLiteral("ssa")}.contains(ext) || info.size()>8*1024*1024) continue;
            const auto stem=info.completeBaseName().normalized(QString::NormalizationForm_KC).toCaseFolded().toUtf8();
            for (const auto& key:SubtitleMatch::keys(std::string_view(stem.constData(),size_t(stem.size())))) {
                auto& candidates=result.matches[QString::fromUtf8(key.data(),qsizetype(key.size()))];
                if(candidates.size()<=MaxCandidates) candidates.push_back(info.absoluteFilePath());
            }
        }
        return result;
    }
private:
    const QString m_path;
    const std::shared_ptr<std::atomic_bool> m_cancel;
};
BulkSubtitleMatch::BulkSubtitleMatch(qt_intf_t* intf,MediaLib* library,QObject* parent)
    :QAbstractListModel(parent),m_intf(intf),m_library(library) {m_pool.setMaxThreadCount(1);}
BulkSubtitleMatch::~BulkSubtitleMatch() {cancelScan();m_pool.waitForDone();}
void BulkSubtitleMatch::cancelScan() {
    if(m_cancel) *m_cancel=true;
    m_scan.reset();m_cancel.reset();
}
int BulkSubtitleMatch::rowCount(const QModelIndex& parent) const { return parent.isValid()?0:int(m_rows.size()); }
QHash<int,QByteArray> BulkSubtitleMatch::roleNames() const { return {{MediaName,"mediaName"},{Choices,"choices"},{Selected,"selectedChoice"}}; }
QVariant BulkSubtitleMatch::data(const QModelIndex& index,int role) const {
    if(!index.isValid()||index.row()<0||size_t(index.row())>=m_rows.size()) return {};
    const auto& row=m_rows[size_t(index.row())];
    if(role==MediaName) return row.name;
    if(role==Selected) return row.selected;
    if(role==Choices) {
        QStringList names{tr("Skip this item")};
        for(const auto& path:row.files) names.push_back(QFileInfo(path).fileName());
        return names;
    }
    return {};
}
bool BulkSubtitleMatch::canApply() const {
    if(loading()||!m_library) return false;
    for(const auto& row:m_rows) if(row.selected>0) return true;
    return false;
}
void BulkSubtitleMatch::prepare() {
    if(loading()) return;
    beginResetModel();m_rows.clear();endResetModel();m_folder.clear();
    m_status=tr("Choose a folder, scan, then review every selection. Ambiguous matches are skipped.");
    {
        vlc_playlist_locker lock{m_intf->p_playlist};
        for(size_t i=0;i<vlc_playlist_Count(m_intf->p_playlist);++i) {
            auto* media=vlc_playlist_item_GetMedia(vlc_playlist_Get(m_intf->p_playlist,i));
            const QUrl url(QString::fromUtf8(media->psz_uri));
            if(url.isLocalFile()&&url.host().isEmpty()&&localPath(url.toLocalFile())) {
                m_folder=QFileInfo(url.toLocalFile()).absolutePath();
                break;
            }
        }
    }
    emit changed();
}
void BulkSubtitleMatch::chooseFolder() {
    if(loading()) return;
    QUrl url(DialogsProvider::getDirectoryDialog(m_intf));
    if(url.scheme()==QStringLiteral("directory")) url.setScheme(QStringLiteral("file"));
    if(url.isLocalFile()&&url.host().isEmpty()) { m_folder=url.toLocalFile(); emit changed(); }
}
void BulkSubtitleMatch::scan(const QString& requestedPath) {
    if(m_applying) return;
    cancelScan();
    beginResetModel(); m_rows.clear(); endResetModel();
    const auto path=QFileInfo(requestedPath).absoluteFilePath();
    if(!localPath(requestedPath)||!QDir(path).exists()) { m_status=tr("Choose an existing local subtitle folder."); emit changed(); return; }
    std::vector<Row> rows;
    {
        vlc_playlist_locker lock{m_intf->p_playlist};
        if(vlc_playlist_Count(m_intf->p_playlist)>MaxQueue) { m_status=tr("Match queues of 200 items or fewer."); emit changed(); return; }
        for(size_t i=0;i<vlc_playlist_Count(m_intf->p_playlist);++i) {
            auto* item=vlc_playlist_Get(m_intf->p_playlist,i);
            auto* media=vlc_playlist_item_GetMedia(item);
            const QUrl url(QString::fromUtf8(media->psz_uri));
            if(!url.isLocalFile()||!url.host().isEmpty()||!localPath(url.toLocalFile())) continue;
            rows.push_back({vlc_playlist_item_GetId(item),SharedInputItem(media,true),QString::fromUtf8(media->psz_uri),QFileInfo(url.toLocalFile()).fileName(),{},0});
        }
    }
    m_folder=path; m_status=tr("Scanning subtitle filenames…");
    m_cancel=std::make_shared<std::atomic_bool>(false);
    m_scan.reset(new SubtitleMatchScanTask(path,m_cancel));
    connect(m_scan.get(),&BaseAsyncTask::result,this,[this,rows=std::move(rows)]() mutable {
        auto result=m_scan->takeResult(); m_scan.reset();m_cancel.reset();
        if(!result.error.isEmpty()) { m_status=result.error; emit changed(); return; }
        int ready=0,ambiguous=0;
        for(auto& row:rows) {
            row.files=result.matches.value(normalise(QFileInfo(row.name).completeBaseName()));
            row.files.removeDuplicates(); row.files.sort(Qt::CaseInsensitive);
            if(row.files.size()>MaxCandidates) { row.files.clear(); ++ambiguous; }
            else if(row.files.size()==1) { row.selected=1; ++ready; }
            else if(row.files.size()>1) ++ambiguous;
        }
        beginResetModel();m_rows=std::move(rows);endResetModel();
        m_status=m_library?tr("%1 queue items · %2 ready · %3 ambiguous. Review before applying.").arg(m_rows.size()).arg(ready).arg(ambiguous)
                          :tr("Enable the media library to persist subtitle matches.");
        emit changed();
    });
    m_scan->start(m_pool,-1);emit changed();
}
void BulkSubtitleMatch::select(int row,int choice) {
    if(loading()||row<0||size_t(row)>=m_rows.size()||choice<0||choice>m_rows[size_t(row)].files.size()) return;
    m_rows[size_t(row)].selected=choice;
    emit dataChanged(index(row,0),index(row,0),{Selected});emit changed();
}
void BulkSubtitleMatch::apply() {
    if(!canApply()) return;
    std::vector<Row> selected;
    for(const auto& row:m_rows) if(row.selected>0) selected.push_back(row);
    struct Context { std::vector<Row> saved; int failed=0; };
    m_applying=true;m_status=tr("Saving subtitle associations…");emit changed();
    m_library->runOnMLThread<Context>(this,[selected=std::move(selected)](vlc_medialibrary_t* ml,Context& context) {
        for(const auto& row:selected) {
            const auto path=row.files[row.selected-1];
            if(!QFileInfo(path).isFile()) { ++context.failed;continue; }
            const auto subtitle=QUrl::fromLocalFile(path).toString(QUrl::FullyEncoded);
            ml_unique_ptr<vlc_ml_media_t> media{vlc_ml_get_media_by_mrl(ml,qtu(row.uri))};
            if(!media) media.reset(vlc_ml_new_external_media(ml,qtu(row.uri)));
            bool exists=false;
            if(media&&media->p_files) for(size_t i=0;i<media->p_files->i_nb_items;++i) {
                const auto& file=media->p_files->p_items[i];
                if(file.i_type==VLC_ML_FILE_TYPE_SUBTITLE&&subtitle==QString::fromUtf8(file.psz_mrl)) exists=true;
            }
            if(media&&(exists||vlc_ml_media_add_external_mrl(ml,media->i_id,qtu(subtitle),VLC_ML_FILE_TYPE_SUBTITLE)==VLC_SUCCESS)) context.saved.push_back(row);
            else ++context.failed;
        }
    },[this](quint64,Context& context) {
        int attached=0;
        for(const auto& row:context.saved) {
            bool present=false;
            {
                vlc_playlist_locker lock{m_intf->p_playlist};
                for(size_t i=0;i<vlc_playlist_Count(m_intf->p_playlist);++i) {
                    auto* item=vlc_playlist_Get(m_intf->p_playlist,i);
                    if(vlc_playlist_item_GetId(item)==row.id&&vlc_playlist_item_GetMedia(item)==row.item.get()) {present=true;break;}
                }
            }
            if(!present) continue; // The library association remains valid after queue removal.
            char* currentUri=input_item_GetURI(row.item.get());
            const bool sameUri=currentUri&&row.uri==QString::fromUtf8(currentUri);
            free(currentUri);
            if(!sameUri) continue;
            const auto subtitle=QUrl::fromLocalFile(row.files[row.selected-1]).toString(QUrl::FullyEncoded).toUtf8();
            bool exists=false;
            {
                vlc::threads::mutex_locker lock{row.item->lock};
                for(int i=0;i<row.item->i_slaves;++i) if(subtitle==row.item->pp_slaves[i]->psz_uri) exists=true;
            }
            if(exists) { ++attached;continue; }
            auto* slave=input_item_slave_New(subtitle.constData(),SLAVE_TYPE_SPU,SLAVE_PRIORITY_USER);
            if(slave&&input_item_AddSlave(row.item.get(),slave)==VLC_SUCCESS) ++attached;
            else { if(slave) input_item_slave_Delete(slave); ++context.failed; }
        }
        m_applying=false;
        m_status=tr("%1 associations saved; %2 queued items updated for their next playback; %3 failed.").arg(context.saved.size()).arg(attached).arg(context.failed);
        if(!context.failed) { for(auto& row:m_rows) row.selected=0; if(!m_rows.empty()) emit dataChanged(index(0,0),index(int(m_rows.size())-1,0),{Selected}); }
        emit changed();
    });
}
