#include "../../modules/gui/qt/player/waveform_envelope.hpp"
#include <cassert>
#include <cmath>
#include <vector>
int main() {
    using Waveform::Envelope;
    std::vector<uint8_t> pcm(16000, 0); // one second, mono 8 kHz
    for (size_t i=0; i<8000; ++i) {
        int sample = i < 2000 || i >= 6000 ? 0 : i < 4000 ? 8192 : -24576;
        const auto raw = uint16_t(sample);
        pcm[i*2] = raw & 255; pcm[i*2+1] = raw >> 8;
    }
    Envelope envelope(1000);
    assert(envelope.append(pcm.data(), pcm.size(), 0));
    const auto& bins = envelope.peaks();
    for(size_t i=0;i<256;++i) {
        const float expected = i<64 || i>=192 ? 0 : i<128 ? 0.25f : 0.75f;
        assert(std::abs(bins[i]-expected)<0.0001f);
    }
    // Streaming chunks preserve bins; gaps are not stretched to fill silence.
    Envelope streamed(1000);
    assert(streamed.append(pcm.data(), 4000, 0));
    assert(streamed.append(pcm.data()+4000, 4000, 2000));
    assert(streamed.append(pcm.data()+8000, 8000, 4000));
    assert(streamed.peaks()==bins);
    Envelope gaps(1000);
    assert(gaps.append(pcm.data()+8000, 2000, 7000));
    assert(gaps.peaks()[0]==0 && gaps.peaks()[240]==0.75f);
    assert(envelope.append(pcm.data(),pcm.size(),UINT64_MAX));
    assert(!envelope.append(nullptr,2,0));
    assert(!envelope.append(pcm.data(),1,0));
    Envelope invalid(0); assert(!invalid.append(pcm.data(),2,0));
    Envelope longFile((Waveform::MaxSeconds+1)*1000); assert(!longFile.append(pcm.data(),2,0));
    // Full-scale negative sample is exactly one, never integer-overflowed.
    uint8_t minimum[2]={0,128}; Envelope full(1);
    assert(full.append(minimum,2,0) && full.peaks()[0]==1.f);
}
