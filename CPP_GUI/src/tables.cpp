#include "tables.hpp"
#include "describe.hpp"
#include "theme.hpp"

#include "imgui.h"

static bool lineChanged(const CacheContents* previous, size_t set, size_t way, const CacheLine& line)
{
    if(!previous || set >= previous->size() || way >= (*previous)[set].size())
        return false;
    const CacheLine& old = (*previous)[set][way];
    return old.state != line.state || old.addr != line.addr || old.data != line.data;
}

static void drawCacheRow(size_t set, size_t way, const CacheLine& line, bool changed)
{
    ImGui::TableNextRow();
    if(changed)
        ImGui::TableSetBgColor(ImGuiTableBgTarget_RowBg1, theme::CHANGED_ROW);

    ImGui::TableSetColumnIndex(0);
    ImGui::Text("%d", (int)set);
    ImGui::TableSetColumnIndex(1);
    ImGui::Text("%d", (int)way);

    ImGui::TableSetColumnIndex(2);
    ImGui::TableSetBgColor(ImGuiTableBgTarget_CellBg, theme::stateColor(line.state));
    ImGui::Text(" %s ", line.state.c_str());

    bool invalid = line.state == "I";
    ImGui::TableSetColumnIndex(3);
    if(invalid)
        ImGui::TextDisabled("-");
    else
        ImGui::Text("%s", shortHex(line.addr).c_str());

    for(size_t k = 0; k < line.data.size(); k++)
    {
        ImGui::TableSetColumnIndex(4 + (int)k);
        if(invalid)
            ImGui::TextDisabled("%s", line.data[k].c_str());
        else
            ImGui::Text("%s", line.data[k].c_str());
    }
}

void drawCacheTable(const char* id, const CacheContents& current, const CacheContents* previous)
{
    if(current.empty() || current[0].empty())
        return;
    int words = (int)current[0][0].data.size();

    ImGui::PushStyleVar(ImGuiStyleVar_CellPadding, ImVec2(5, 2));
    ImGuiTableFlags flags = ImGuiTableFlags_Borders | ImGuiTableFlags_RowBg | ImGuiTableFlags_SizingFixedFit;
    if(ImGui::BeginTable(id, 4 + words, flags))
    {
        ImGui::TableSetupColumn("Set");
        ImGui::TableSetupColumn("Way");
        ImGui::TableSetupColumn("St.");
        ImGui::TableSetupColumn("Line");
        for(int k = 0; k < words; k++)
            ImGui::TableSetupColumn(("W" + std::to_string(k)).c_str());
        ImGui::TableHeadersRow();

        for(size_t s = 0; s < current.size(); s++)
        {
            for(size_t w = 0; w < current[s].size(); w++)
                drawCacheRow(s, w, current[s][w], lineChanged(previous, s, w, current[s][w]));
        }

        ImGui::EndTable();
    }
    ImGui::PopStyleVar();
}

void drawMemoryTable(const Step& step, int wordsPerLine)
{
    ImGui::Text("Main memory");
    ImGui::SameLine();
    ImGui::TextDisabled(
        "  lines written so far; every other word still holds its initial value (word at address A = A)");

    if(step.memory.empty())
    {
        ImGui::TextDisabled("No write-backs yet.");
        return;
    }
    if(!ImGui::BeginTable("memory", 1 + wordsPerLine, ImGuiTableFlags_Borders | ImGuiTableFlags_SizingFixedFit))
        return;

    ImGui::TableSetupColumn("Line");
    for(int k = 0; k < wordsPerLine; k++)
        ImGui::TableSetupColumn(("Word " + std::to_string(k)).c_str());
    ImGui::TableHeadersRow();

    for(const auto& [addr, words] : step.memory)
    {
        ImGui::TableNextRow();
        if(addr == step.memoryWritten)
            ImGui::TableSetBgColor(ImGuiTableBgTarget_RowBg1, theme::CHANGED_ROW);
        ImGui::TableSetColumnIndex(0);
        ImGui::Text("%s", shortHex(addr).c_str());
        for(size_t k = 0; k < words.size(); k++)
        {
            ImGui::TableSetColumnIndex(1 + (int)k);
            ImGui::Text("%s", words[k].c_str());
        }
    }
    ImGui::EndTable();
}
