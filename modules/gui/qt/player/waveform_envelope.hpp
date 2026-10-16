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
#ifndef WAVEFORM_ENVELOPE_HPP
#define WAVEFORM_ENVELOPE_HPP
#include <array>
#include <algorithm>
#include <cstddef>
#include <cstdint>

namespace Waveform {
constexpr size_t BinCount = 256;
constexpr uint64_t Rate = 8000;
constexpr uint64_t MaxSeconds = 6 * 60 * 60;
/** Constant-memory peak envelope. Input is mono, signed little-endian PCM16. */
class Envelope {
public:
    explicit Envelope(uint64_t durationMs) : m_frames(durationMs * Rate / 1000) {}
    bool append(const uint8_t* data, size_t bytes, uint64_t firstFrame) {
        if (!data || bytes % 2 || !m_frames || m_frames > MaxSeconds * Rate)
            return false;
        if (firstFrame >= m_frames) return true;
        const size_t count = size_t(std::min<uint64_t>(bytes / 2, m_frames - firstFrame));
        for (size_t i = 0; i < count; ++i) {
            const uint64_t frame = firstFrame + i;
            const unsigned raw = unsigned(data[2*i]) | (unsigned(data[2*i+1]) << 8);
            const int value = raw >= 32768 ? int(raw) - 65536 : int(raw);
            const float amplitude = float(value < 0 ? -value : value) / 32768.f;
            auto& peak = m_peaks[size_t(frame * BinCount / m_frames)];
            peak = std::max(peak, amplitude);
        }
        return true;
    }
    const std::array<float, BinCount>& peaks() const { return m_peaks; }
private:
    uint64_t m_frames;
    std::array<float, BinCount> m_peaks{};
};
}
#endif
