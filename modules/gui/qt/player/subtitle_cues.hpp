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
#ifndef SUBTITLE_CUES_HPP
#define SUBTITLE_CUES_HPP
#include <algorithm>
#include <charconv>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// Source-time cues only. Decoder rendering, track selection and subtitle formats remain VLC's.
namespace SubtitleCues {
struct Cue { int64_t start; int64_t end; std::string text; };
constexpr size_t MaxFileBytes = 8 * 1024 * 1024;
constexpr size_t MaxCues = 50000;
constexpr size_t MaxTextBytes = 8192;

inline std::string_view trim(std::string_view s)
{
    const auto first = s.find_first_not_of(" \t\r\n");
    if (first == s.npos) return {};
    return s.substr(first, s.find_last_not_of(" \t\r\n") - first + 1);
}
inline std::optional<int64_t> timestamp(std::string_view s)
{
    s = trim(s);
    // WebVTT permits MM:SS.mmm; SRT uses HH:MM:SS,mmm.
    const auto fraction = s.find_last_of(".,");
    if (fraction == s.npos || s.size() - fraction != 4) return {};
    int64_t parts[4] = {};
    auto parse = [](std::string_view text, int64_t& value) {
        if (text.empty() || text.front() < '0' || text.front() > '9') return false;
        const auto result = std::from_chars(text.data(), text.data() + text.size(), value);
        return result.ec == std::errc() && result.ptr == text.data() + text.size();
    };
    if (!parse(s.substr(fraction + 1), parts[3])) return {};
    s = s.substr(0, fraction);
    int count = 0;
    while (count < 3) {
        const auto colon = s.find_last_of(':');
        const auto field = colon == s.npos ? s : s.substr(colon + 1);
        if (!parse(field, parts[2 - count++])) return {};
        if (colon == s.npos) { s = {}; break; }
        s = s.substr(0, colon);
    }
    if (!s.empty() || count < 2 || parts[0] > 999999 || parts[1] > 59 || parts[2] > 59)
        return {};
    return ((parts[0] * 60 + parts[1]) * 60 + parts[2]) * 1000 + parts[3];
}
inline std::vector<Cue> parse(std::string_view input)
{
    std::vector<Cue> cues;
    if (input.size() > MaxFileBytes) return cues;
    if (input.substr(0, 3) == "\xef\xbb\xbf") input.remove_prefix(3);
    Cue cue{};
    bool haveCue = false;
    bool skipBlock = false;
    auto finish = [&]() {
        if (haveCue && !cue.text.empty() && cues.size() < MaxCues)
            cues.push_back(std::move(cue));
        cue = {}; haveCue = false;
    };
    while (!input.empty() && cues.size() < MaxCues) {
        const auto newline = input.find('\n');
        const auto line = trim(input.substr(0, newline));
        input = newline == input.npos ? std::string_view{} : input.substr(newline + 1);
        if (line.empty()) { finish(); skipBlock = false; continue; }
        if (!haveCue && (line == "STYLE" || line == "REGION" || line == "NOTE" ||
                         line.substr(0, 5) == "NOTE ")) skipBlock = true;
        if (skipBlock) continue;
        const auto arrow = line.find("-->");
        if (arrow != line.npos && line.front() >= '0' && line.front() <= '9') {
            // Cue identifiers are optional. Accept a missing blank separator too.
            finish();
            const auto endToken = trim(line.substr(arrow + 3));
            const auto start = timestamp(line.substr(0, arrow));
            const auto end = timestamp(endToken.substr(0, endToken.find_first_of(" \t")));
            if (start && end && *end > *start) {
                cue.start = *start; cue.end = *end; haveCue = true;
            }
        } else if (haveCue && cue.text.size() < MaxTextBytes) {
            if (!cue.text.empty()) cue.text += '\n';
            cue.text.append(line.substr(0, MaxTextBytes - cue.text.size()));
        }
    }
    finish();
    std::stable_sort(cues.begin(), cues.end(), [](const Cue& a, const Cue& b) {return a.start < b.start;});
    return cues;
}
}
#endif
