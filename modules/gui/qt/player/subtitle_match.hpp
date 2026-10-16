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
#ifndef SUBTITLE_MATCH_HPP
#define SUBTITLE_MATCH_HPP
#include <string>
#include <string_view>
#include <vector>
#include <set>
namespace SubtitleMatch {
inline std::string normalise(std::string_view value) {
    std::string result;
    for (unsigned char c : value) {
        if (c == '.' || c == '_' || c == '-' || c == ' ' || c == '[' || c == ']' || c == '(' || c == ')') {
            if (!result.empty() && result.back() != ' ') result.push_back(' ');
        } else result.push_back(c >= 'A' && c <= 'Z' ? char(c + 'a' - 'A') : char(c));
    }
    if (!result.empty() && result.back() == ' ') result.pop_back();
    return result;
}
inline std::vector<std::string> keys(std::string_view subtitleStem) {
    static const std::set<std::string> tags = {
        "en","eng","english","es","spa","spanish","pt","por","portuguese","br","ptbr",
        "fr","fra","fre","french","de","deu","ger","german","it","ita","nl","nld","dut",
        "ja","jpn","ko","kor","zh","zho","chi","ru","rus","uk","ukr","ar","ara",
        "hi","hin","pl","pol","tr","tur","sv","swe","da","dan","fi","fin","no","nor",
        "us","gb","forced","sdh","cc","hearing","impaired","subtitles","subs"
    };
    std::vector<std::string> result;
    if (subtitleStem.size() > 512) return result;
    auto key = normalise(subtitleStem);
    if (key.empty()) return result;
    result.push_back(key);
    for (unsigned suffix = 0; suffix < 4; ++suffix) {
        auto at = key.rfind(' ');
        if (at == std::string::npos || !tags.count(key.substr(at+1))) break;
        key.resize(at); result.push_back(key);
    }
    return result;
}
}
#endif
