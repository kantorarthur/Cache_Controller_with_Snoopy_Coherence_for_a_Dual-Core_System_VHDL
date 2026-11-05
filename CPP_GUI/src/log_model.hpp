#pragma once

#include <nlohmann/json.hpp>
#include <map>
#include <string>
#include <vector>

using json = nlohmann::json;

struct CacheLine
{
    std::string state = "I";
    std::string addr = "00000000";
    std::vector<std::string> data;
};

using CacheContents = std::vector<std::vector<CacheLine>>;

struct Step
{
    json event;
    std::string type;
    int time = 0;
    CacheContents cache[2];
    json lastCpu[2];
    std::string scenarioName;
    std::map<std::string, std::vector<std::string>> memory;
    std::string memoryWritten;
    std::string title;
    std::vector<std::string> details;
};

struct Scenario
{
    int firstStep;
    std::string name;
};

struct SimLog
{
    int sets = 0;
    int ways = 0;
    int lineSize = 16;
    std::string policy;
    std::vector<Step> steps;
    std::vector<Scenario> scenarios;
    int errors = -1;
    std::string loadError;

    bool ok() const
    {
        return loadError.empty() && !steps.empty();
    }
    int wordsPerLine() const
    {
        return lineSize / 4;
    }
};

SimLog loadSimLog(const std::string& path);
