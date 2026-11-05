#include "describe.hpp"

std::string shortHex(const std::string& hex)
{
    size_t i = 0;
    while(i + 3 < hex.size() && hex[i] == '0')
        i++;
    return "0x" + hex.substr(i);
}

static std::string commandReason(const std::string& cmd)
{
    if(cmd == "BusRd")
        return "read miss: it needs a copy of the line";
    if(cmd == "BusRdX")
        return "write miss: it needs an exclusive copy of the line";
    if(cmd == "BusUpgr")
        return "write hit on a Shared line: the other copies must be invalidated";
    if(cmd == "Flush")
        return "the victim line is Modified, so it is written back before being replaced";
    return "";
}

static std::string describeCpu(const json& e)
{
    std::string core = std::to_string(e.value("core", 0));
    std::string result = e.value("result", "");
    std::string addr = shortHex(e.value("addr", ""));
    std::string value = shortHex(e.value("value", ""));
    if(e.value("op", "") == "W")
        return "Core " + core + " wrote " + value + " to " + addr + " (" + result + ")";
    return "Core " + core + " read " + addr + " = " + value + " (" + result + ")";
}

static std::string describeBusStart(const json& e)
{
    std::string cmd = e.value("cmd", "");
    return "Cache " + std::to_string(e.value("core", 0)) + " gets the bus and issues " + cmd + " for line " +
           shortHex(e.value("addr", "")) + " (" + commandReason(cmd) + ")";
}

static std::string describeBusEnd(const json& e)
{
    std::string requester = std::to_string(e.value("core", 0));
    std::string cmd = e.value("cmd", "");
    std::string source = e.value("source", "");
    std::string addr = shortHex(e.value("addr", ""));
    if(cmd == "Flush")
        return "Write-back done: memory now holds the modified line " + addr;
    if(cmd == "BusUpgr")
        return "BusUpgr done: cache " + requester + " owns line " + addr + " in M";
    if(source == "memory")
        return cmd + " done: memory supplies line " + addr + " to cache " + requester;
    return cmd + " done: cache " + source.substr(5) + " held line " + addr +
           " in M, so it sends the data directly to cache " + requester + " (cache-to-cache) and memory is updated";
}

std::string describeEvent(const json& e)
{
    std::string type = e.value("type", "");
    if(type == "scenario")
        return "Scenario " + e.value("name", "");
    if(type == "cpu")
        return describeCpu(e);
    if(type == "bus_start")
        return describeBusStart(e);
    if(type == "bus_end")
        return describeBusEnd(e);
    if(type == "end")
    {
        int n = e.value("errors", 0);
        if(n == 0)
            return "Simulation finished: all checks passed";
        return "Simulation finished: " + std::to_string(n) + " check(s) failed";
    }
    return type;
}

std::string briefEvent(const Step& step)
{
    const json& e = step.event;
    if(step.type == "bus_start")
    {
        std::string core = std::to_string(e.value("core", 0));
        return "Cache " + core + ": " + e.value("cmd", "") + " " + shortHex(e.value("addr", ""));
    }
    if(step.type == "bus_end")
    {
        std::string source = e.value("source", "");
        std::string text = "  " + e.value("cmd", "") + " done";
        if(source != "none")
            text += " (data from " + source + ")";
        return text;
    }
    return step.title;
}

void describeCacheChanges(int cacheId, const CacheContents& before, const CacheContents& after,
                          std::vector<std::string>& out)
{
    for(size_t s = 0; s < before.size() && s < after.size(); s++)
    {
        for(size_t w = 0; w < before[s].size() && w < after[s].size(); w++)
        {
            const CacheLine& x = before[s][w];
            const CacheLine& y = after[s][w];
            std::string where =
                "Cache " + std::to_string(cacheId) + ", set " + std::to_string(s) + ", way " + std::to_string(w) + ": ";
            if(x.addr != y.addr && y.state != "I")
            {
                std::string oldLine = shortHex(x.addr) + " (" + x.state + ")";
                std::string newLine = shortHex(y.addr) + " (" + y.state + ")";
                if(x.state == "I")
                    out.push_back(where + "line " + newLine + " loaded");
                else
                    out.push_back(where + "line " + oldLine + " replaced by " + newLine);
            }
            else if(x.state != y.state)
                out.push_back(where + "line " + shortHex(y.addr) + " " + x.state + " -> " + y.state);
            else if(x.data != y.data)
                out.push_back(where + "data written in line " + shortHex(y.addr));
        }
    }
}
