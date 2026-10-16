#include "../../modules/gui/qt/player/subtitle_match.hpp"
#include <cassert>
#include <algorithm>
bool matches(const std::string& video,const std::string& subtitle) {
 const auto keys=SubtitleMatch::keys(subtitle);
 return std::find(keys.begin(),keys.end(),SubtitleMatch::normalise(video))!=keys.end();
}
int main() {
 assert(matches("Show.S01E01","Show.S01E01.en"));
 assert(matches("Show_S01E01","show.s01e01.pt-BR.forced"));
 assert(matches("A film (2025)","A film [2025].eng.sdh"));
 assert(!matches("Show S01E01","Show S01E02.en"));
 assert(!matches("Show S01E01","Other Show S01E01.en"));
 assert(!matches("Show S01E01","Show S01E01 1080p"));
 assert(matches("Épisode 1","Épisode 1.fr"));
 assert(SubtitleMatch::keys(std::string(513,'x')).empty());
 assert(SubtitleMatch::keys("").empty());
}
