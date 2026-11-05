#pragma once

#include "log_model.hpp"

#include <string>
#include <vector>

std::string shortHex(const std::string& hex);

std::string describeEvent(const json& event);

std::string briefEvent(const Step& step);

void describeCacheChanges(int cacheId, const CacheContents& before, const CacheContents& after,
                          std::vector<std::string>& out);
