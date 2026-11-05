#include "log_model.hpp"
#include "describe.hpp"

#include <fstream>

static CacheContents emptyCache(int sets, int ways, int words)
{
    CacheLine line;
    line.data.assign(words, "00000000");
    return CacheContents(sets, std::vector<CacheLine>(ways, line));
}

static CacheContents parseCache(const json& j)
{
    CacheContents cache;
    for(const auto& set : j)
    {
        std::vector<CacheLine> row;
        for(const auto& way : set)
        {
            CacheLine line;
            line.state = way.at("state").get<std::string>();
            line.addr = way.at("addr").get<std::string>();
            for(const auto& word : way.at("data"))
                line.data.push_back(word.get<std::string>());
            row.push_back(line);
        }
        cache.push_back(row);
    }
    return cache;
}

static void applyConfig(SimLog& log, Step& base, const json& e)
{
    log.sets = e.value("sets", 0);
    log.ways = e.value("ways", 0);
    log.lineSize = e.value("line_size", 16);
    log.policy = e.value("policy", "");
    base.cache[0] = emptyCache(log.sets, log.ways, log.wordsPerLine());
    base.cache[1] = base.cache[0];
}

static void applyState(SimLog& log, Step& base, const json& e)
{
    CacheContents next[2] = {parseCache(e.at("cache0")), parseCache(e.at("cache1"))};
    Step& target = log.steps.empty() ? base : log.steps.back();
    for(int c = 0; c < 2; c++)
    {
        if(!log.steps.empty())
            describeCacheChanges(c, target.cache[c], next[c], target.details);
        target.cache[c] = next[c];
    }
}

static Step makeStep(SimLog& log, const Step& previous, const json& e)
{
    Step step = previous;
    step.event = e;
    step.type = e.value("type", "");
    step.time = e.value("t", 0);
    step.title = describeEvent(e);
    step.details.clear();
    step.memoryWritten.clear();

    if(step.type == "scenario")
    {
        step.scenarioName = e.value("name", "");
        log.scenarios.push_back({(int)log.steps.size(), step.scenarioName});
    }
    else if(step.type == "cpu")
        step.lastCpu[e.value("core", 0)] = e;
    else if(step.type == "bus_end" && e.value("mem_write", false))
    {
        std::vector<std::string> words;
        for(const auto& w : e.at("data"))
            words.push_back(w.get<std::string>());
        step.memory[e.value("addr", "")] = words;
        step.memoryWritten = e.value("addr", "");
    }
    else if(step.type == "end")
        log.errors = e.value("errors", 0);
    return step;
}

SimLog loadSimLog(const std::string& path)
{
    SimLog log;
    std::ifstream file(path);
    if(!file)
    {
        log.loadError = "Cannot open " + path;
        return log;
    }

    Step base;
    std::string text;
    int lineNo = 0;
    while(std::getline(file, text))
    {
        lineNo++;
        if(text.empty() || text == "\r")
            continue;

        json e;
        try
        {
            e = json::parse(text);
        }
        catch(const std::exception&)
        {
            log.loadError = "Invalid JSON at line " + std::to_string(lineNo);
            return log;
        }

        std::string type = e.value("type", "");
        if(type == "config")
            applyConfig(log, base, e);
        else if(type == "state")
            applyState(log, base, e);
        else
            log.steps.push_back(makeStep(log, log.steps.empty() ? base : log.steps.back(), e));
    }

    if(log.steps.empty() && log.loadError.empty())
        log.loadError = "The log file is empty";
    return log;
}
