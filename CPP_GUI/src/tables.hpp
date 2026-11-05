#pragma once

#include "log_model.hpp"

void drawCacheTable(const char* id, const CacheContents& current, const CacheContents* previous);

void drawMemoryTable(const Step& step, int wordsPerLine);
