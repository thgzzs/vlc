// GPL-2.0-or-later; native source-time parser regression tests.
#include "../../modules/gui/qt/player/subtitle_cues.hpp"
#include <cassert>
#include <iostream>
#include <random>

int main()
{
    using namespace SubtitleCues;
    assert(timestamp("01:02:03,456") == 3723456);
    assert(timestamp("02:03.456") == 123456);
    for (auto invalid : {"00:99:00,000", "-1:00:00,000", "00:00:60,000", "00:00:00,0",
                         "00:00:00,000x", "1:2:3:4.567", "999999999999999999999:00:00,000", "NaN"})
        assert(!timestamp(invalid));

    auto srt = parse("\xef\xbb\xbf" "1\r\n00:00:01,000 --> 00:00:03,000\r\nOlá 世界\r\nSecond line\r\n\r\n2\r\n00:00:02,000 --> 00:00:04,000\r\nOverlap");
    assert(srt.size() == 2 && srt[0].start == 1000 && srt[0].end == 3000);
    assert(srt[0].text == "Olá 世界\nSecond line");
    assert(srt[1].start == 2000 && srt[1].end == 4000);

    auto arrowText = parse("00:00:01,000 --> 00:00:02,000\nA --> B");
    assert(arrowText.size() == 1 && arrowText[0].text == "A --> B");
    auto vtt = parse("WEBVTT\n\nNOTE Ignore this block\n00:01.000 --> 00:02.000\nHidden\n\n"
                     "STYLE\n::cue { color: white; }\n\n"
                     "second\n00:03.000 --> 00:04.500 align:start position:10%\nLater\n\n"
                     "first\n00:01.000 --> 00:02.000\nEarlier\n");
    assert(vtt.size() == 2 && vtt[0].text == "Earlier" && vtt[1].end == 4500);
    assert(parse("00:00:02,000 --> 00:00:01,000\nReversed\n").empty());
    assert(parse("00:00:01,000 --> 00:00:01,000\nZero length\n").empty());
    assert(parse("00:99:01,000 --> 00:00:03,000\nMalformed\n").empty());
    assert(parse(std::string(MaxFileBytes + 1, 'x')).empty());
    auto longText = parse("00:00:01,000 --> 00:00:02,000\n" + std::string(MaxTextBytes + 100, 'x'));
    assert(longText.size() == 1 && longText[0].text.size() == MaxTextBytes);
    std::string many;
    for (size_t i = 0; i < MaxCues + 5; ++i)
        many += "00:00:01,000 --> 00:00:02,000\nCue\n\n";
    assert(parse(many).size() == MaxCues);
    assert(parse("00:00:02,000 --> 00:00:03,000\nSecond\n00:00:01,000 --> 00:00:02,000\nFirst")[0].text == "First");

    // Deterministic malformed-input coverage under undefined-behaviour sanitization.
    std::mt19937 random(724);
    for (int n = 0; n < 10000; ++n) {
        std::string input(random() % 2048, ' ');
        for (auto& c : input) c = char(random() & 255);
        (void)parse(input);
    }
    std::cout << "Subtitle cue parser: all regression and malformed-input checks passed\n";
}
