#include "diagram.hpp"
#include "describe.hpp"
#include "theme.hpp"

#include "imgui.h"

namespace
{

enum class Flow
{
    None,
    Up,
    Down,
    Active
};

struct Highlight
{
    int cpuCore = -1;
    int requester = -1;
    int source = -1;
    bool bus = false;
    Flow cacheLink[2] = {Flow::None, Flow::None};
    Flow memoryLink = Flow::None;
    std::string busLabel;
    std::string cpuLabel;
};

struct Layout
{
    float left, right, center, width;
    float coreY, cacheY, busY, memoryY;
    ImVec2 coreSize{190, 40};
    ImVec2 cacheSize{190, 52};
    ImVec2 memorySize{190, 40};

    Layout(ImVec2 origin, float w)
        : left(origin.x + w * 0.25f), right(origin.x + w * 0.75f), center(origin.x + w * 0.5f), width(w),
          coreY(origin.y + 30), cacheY(origin.y + 115), busY(origin.y + 190), memoryY(origin.y + 240)
    {
    }

    float coreX(int c) const
    {
        return c == 0 ? left : right;
    }
};

Highlight cpuHighlight(const json& e)
{
    Highlight h;
    h.cpuCore = e.value("core", 0);
    h.cpuLabel = std::string(e.value("op", "") == "W" ? "W " : "R ") + shortHex(e.value("addr", "")) + " = " +
                 shortHex(e.value("value", "")) + "  " + e.value("result", "");
    return h;
}

Highlight busStartHighlight(const json& e)
{
    Highlight h;
    std::string cmd = e.value("cmd", "");
    h.bus = true;
    h.requester = e.value("core", 0);
    h.cacheLink[h.requester] = Flow::Down;
    if(cmd != "BusUpgr")
        h.memoryLink = Flow::Down;
    h.busLabel = cmd + " " + shortHex(e.value("addr", "")) + "   (cache " + std::to_string(h.requester) + ")";
    return h;
}

Highlight busEndHighlight(const json& e)
{
    Highlight h;
    std::string cmd = e.value("cmd", "");
    std::string source = e.value("source", "");
    std::string addr = shortHex(e.value("addr", ""));
    h.bus = true;
    h.requester = e.value("core", 0);
    std::string req = std::to_string(h.requester);

    if(source == "cache0")
        h.source = 0;
    if(source == "cache1")
        h.source = 1;
    if(source == "memory")
        h.memoryLink = Flow::Up;
    if(e.value("mem_write", false))
        h.memoryLink = Flow::Down;

    if(cmd == "Flush")
    {
        h.cacheLink[h.requester] = Flow::Down;
        h.busLabel = "line " + addr + "  cache " + req + " -> memory";
    }
    else if(cmd == "BusUpgr")
    {
        h.cacheLink[h.requester] = Flow::Active;
        h.busLabel = "BusUpgr " + addr + " done";
    }
    else
    {
        h.cacheLink[h.requester] = Flow::Up;
        if(h.source >= 0)
        {
            h.cacheLink[h.source] = Flow::Down;
            h.busLabel = "line " + addr + "  cache " + std::to_string(h.source) + " -> cache " + req + " + memory";
        }
        else
            h.busLabel = "line " + addr + "  memory -> cache " + req;
    }
    return h;
}

Highlight highlightFor(const Step& step)
{
    if(step.type == "cpu")
        return cpuHighlight(step.event);
    if(step.type == "bus_start")
        return busStartHighlight(step.event);
    if(step.type == "bus_end")
        return busEndHighlight(step.event);
    return {};
}

void drawLink(ImDrawList* dl, float x, float yTop, float yBottom, Flow flow)
{
    bool active = flow != Flow::None;
    ImU32 color = active ? theme::ACCENT : theme::IDLE;
    float thickness = active ? 4.0f : 2.0f;
    dl->AddLine(ImVec2(x, yTop), ImVec2(x, yBottom), color, thickness);
    if(flow == Flow::Down)
        dl->AddTriangleFilled(ImVec2(x, yBottom), ImVec2(x - 7, yBottom - 11), ImVec2(x + 7, yBottom - 11), color);
    if(flow == Flow::Up)
        dl->AddTriangleFilled(ImVec2(x, yTop), ImVec2(x - 7, yTop + 11), ImVec2(x + 7, yTop + 11), color);
}

void drawBox(ImDrawList* dl, ImVec2 center, ImVec2 size, const std::string& title, const std::string& subtitle,
             bool active)
{
    ImVec2 p0(center.x - size.x / 2, center.y - size.y / 2);
    ImVec2 p1(center.x + size.x / 2, center.y + size.y / 2);
    dl->AddRectFilled(p0, p1, theme::BOX, 8.0f);
    dl->AddRect(p0, p1, active ? theme::ACCENT : theme::IDLE, 8.0f, 0, active ? 3.0f : 1.5f);

    ImVec2 titleSize = ImGui::CalcTextSize(title.c_str());
    float y = subtitle.empty() ? center.y - titleSize.y / 2 : center.y - titleSize.y;
    dl->AddText(ImVec2(center.x - titleSize.x / 2, y), theme::TEXT, title.c_str());
    if(!subtitle.empty())
    {
        ImVec2 subSize = ImGui::CalcTextSize(subtitle.c_str());
        dl->AddText(ImVec2(center.x - subSize.x / 2, y + titleSize.y + 2), theme::TEXT_DIM, subtitle.c_str());
    }
}

std::string stateCounts(const CacheContents& cache)
{
    int m = 0, s = 0;
    for(const auto& set : cache)
    {
        for(const auto& line : set)
        {
            if(line.state == "M")
                m++;
            if(line.state == "S")
                s++;
        }
    }
    return "M: " + std::to_string(m) + "   S: " + std::to_string(s);
}

void drawBus(ImDrawList* dl, const Layout& L, ImVec2 origin, const Highlight& h)
{
    ImVec2 p0(origin.x + 20, L.busY - 5);
    ImVec2 p1(origin.x + L.width - 20, L.busY + 5);
    dl->AddRectFilled(p0, p1, h.bus ? theme::ACCENT : theme::IDLE, 4.0f);
    dl->AddText(ImVec2(origin.x + 24, L.busY - 26), theme::TEXT_DIM, "Shared bus");
    if(!h.busLabel.empty())
    {
        ImVec2 size = ImGui::CalcTextSize(h.busLabel.c_str());
        dl->AddText(ImVec2(L.center - size.x / 2, L.busY - 26), theme::TEXT, h.busLabel.c_str());
    }
}

} // namespace

void drawSystemDiagram(const Step& step, float width)
{
    const float height = 270.0f;
    ImDrawList* dl = ImGui::GetWindowDrawList();
    ImVec2 origin = ImGui::GetCursorScreenPos();
    ImGui::Dummy(ImVec2(width, height));

    Layout L(origin, width);
    Highlight h = highlightFor(step);

    for(int c = 0; c < 2; c++)
    {
        float x = L.coreX(c);
        drawLink(dl, x, L.coreY + L.coreSize.y / 2, L.cacheY - L.cacheSize.y / 2,
                 h.cpuCore == c ? Flow::Active : Flow::None);
        if(h.cpuCore == c)
            dl->AddText(ImVec2(x + 10, (L.coreY + L.cacheY) / 2 - 8), theme::ACCENT, h.cpuLabel.c_str());
        drawLink(dl, x, L.cacheY + L.cacheSize.y / 2, L.busY - 5, h.cacheLink[c]);
    }
    drawLink(dl, L.center, L.busY + 5, L.memoryY - L.memorySize.y / 2, h.memoryLink);
    drawBus(dl, L, origin, h);

    for(int c = 0; c < 2; c++)
    {
        float x = L.coreX(c);
        bool cacheActive = h.cpuCore == c || h.requester == c || h.source == c;
        drawBox(dl, ImVec2(x, L.coreY), L.coreSize, "Core " + std::to_string(c), "", h.cpuCore == c);
        drawBox(dl, ImVec2(x, L.cacheY), L.cacheSize, "Cache " + std::to_string(c), stateCounts(step.cache[c]),
                cacheActive);
    }
    drawBox(dl, ImVec2(L.center, L.memoryY), L.memorySize, "Main memory", "", h.memoryLink != Flow::None);
}
