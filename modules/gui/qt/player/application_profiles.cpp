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
#include "application_profiles.hpp"
#include "player/rd_effects.hpp"
#include "maininterface/mainctx.hpp"
#include "util/color_scheme_model.hpp"
#include <QColor>
#include <QSettings>

namespace {
const QString storageKey = QStringLiteral("Redesign/ApplicationProfilesV1");
// Deliberately explicit: passwords, paths, privacy and network settings are not profile fields.
const QStringList optionNames = {
    QStringLiteral("audio"), QStringLiteral("video"), QStringLiteral("audio-language"),
    QStringLiteral("sub-language"), QStringLiteral("audio-time-stretch"),
    QStringLiteral("audio-replay-gain-mode"), QStringLiteral("audio-replay-gain-preamp"),
    QStringLiteral("audio-replay-gain-default"), QStringLiteral("audio-replay-gain-peak-protection"),
    QStringLiteral("volume-save"), QStringLiteral("avcodec-hw"), QStringLiteral("drop-late-frames"),
    QStringLiteral("skip-frames"), QStringLiteral("deinterlace"), QStringLiteral("deinterlace-mode"),
    QStringLiteral("video-title-show"), QStringLiteral("video-title-position"),
    QStringLiteral("sub-autodetect-file"), QStringLiteral("subsdec-formatted"),
    QStringLiteral("subsdec-encoding"), QStringLiteral("sub-fps"), QStringLiteral("sub-delay"),
    QStringLiteral("sub-margin"), QStringLiteral("sub-text-scale"),
    QStringLiteral("freetype-font"), QStringLiteral("freetype-rel-fontsize"),
    QStringLiteral("freetype-bold"), QStringLiteral("freetype-color"),
    QStringLiteral("freetype-opacity"), QStringLiteral("freetype-outline-color"),
    QStringLiteral("freetype-outline-thickness"), QStringLiteral("freetype-background-color"),
    QStringLiteral("freetype-background-opacity")
};
}
ApplicationProfiles::ApplicationProfiles(qt_intf_t* intf, MainCtx* ctx, RdEffects* effects, QObject* parent)
    : QObject(parent), m_intf(intf), m_ctx(ctx), m_effects(effects)
{
    m_records = intf->mainSettings->value(storageKey).toMap();
    if (m_records.size() > 32) m_records.clear();
}
QStringList ApplicationProfiles::names() const {
    auto result = m_records.keys(); result.sort(Qt::CaseInsensitive); return result;
}
bool ApplicationProfiles::persist(const QVariantMap& records) {
    m_intf->mainSettings->setValue(storageKey, records);
    m_intf->mainSettings->sync();
    if (m_intf->mainSettings->status() != QSettings::NoError) {
        m_error = tr("Could not save application profiles."); emit changed(); return false;
    }
    m_records = records; m_error.clear(); emit changed(); return true;
}
bool ApplicationProfiles::save(const QString& requestedName) {
    const auto name = requestedName.trimmed();
    if (name.isEmpty() || name.size() > 80 || name.contains(QChar::Null)) {
        m_error = tr("Enter a profile name of 1 to 80 characters."); emit changed(); return false;
    }
    if (m_records.contains(name)) {
        m_error = tr("That profile already exists. Use another name."); emit changed(); return false;
    }
    if (m_records.size() >= 32) {
        m_error = tr("Up to 32 application profiles can be saved."); emit changed(); return false;
    }
    QVariantMap values;
    for (const auto& option : optionNames) {
        if (config_GetType(option.toUtf8().constData()) != 0)
            values.insert(option, m_effects->option(option));
    }
    const QVariantMap record{
        {QStringLiteral("version"), 1}, {QStringLiteral("options"), values},
        {QStringLiteral("theme"), m_ctx->getColorScheme()->currentIndex()},
        {QStringLiteral("accent"), m_ctx->accentColor().isValid() ? m_ctx->accentColor().name(QColor::HexRgb) : QStringLiteral("default")}
    };
    auto records = m_records; records.insert(name, record); return persist(records);
}
bool ApplicationProfiles::apply(const QString& name) {
    const auto record = m_records.value(name).toMap();
    if (record.value(QStringLiteral("version")).toInt() != 1) {
        m_error = tr("Select a valid application profile."); emit changed(); return false;
    }
    const auto values = record.value(QStringLiteral("options")).toMap();
    // Restore only known fields; future/unknown fields cannot become arbitrary VLC options.
    for (const auto& option : optionNames) {
        if (values.contains(option) && config_GetType(option.toUtf8().constData()) != 0)
            m_effects->setOption(option, values.value(option));
    }
    const auto accent = record.value(QStringLiteral("accent")).toString();
    const auto color = QColor(accent);
    if (accent == QStringLiteral("default")) m_ctx->setAccentColor(QColor());
    else if (color.isValid()) m_ctx->setAccentColor(color);
    const int theme = record.value(QStringLiteral("theme"), -1).toInt();
    auto* schemes = m_ctx->getColorScheme();
    if (theme >= 0 && theme < schemes->rowCount({})) schemes->setCurrentIndex(theme);
    m_error.clear(); emit changed(); return true;
}
bool ApplicationProfiles::remove(const QString& name) {
    if (!m_records.contains(name)) return false;
    auto records = m_records; records.remove(name); return persist(records);
}
