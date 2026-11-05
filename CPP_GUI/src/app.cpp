#include "app.hpp"
#include "describe.hpp"
#include "diagram.hpp"
#include "tables.hpp"
#include "theme.hpp"

#include "imgui.h"

#include <cstdio>

App::App(const std::string& logPath)
{
    std::snprintf(path_, sizeof(path_), "%s", logPath.c_str());
    load();
}

void App::load()
{
    log_ = loadSimLog(path_);
    player_.reset((int)log_.steps.size());
}

void App::frame(double now)
{
    handleKeys(now);
    player_.update(now);

    const ImGuiIO& io = ImGui::GetIO();
    ImGui::SetNextWindowPos(ImVec2(0, 0));
    ImGui::SetNextWindowSize(io.DisplaySize);
    ImGui::Begin("main", nullptr,
                 ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize |
                     ImGuiWindowFlags_NoBringToFrontOnFocus);

    drawToolbar(now);
    ImGui::Separator();

    if(log_.ok())
    {
        drawSidebar();
        ImGui::SameLine();
        drawStepView();
    }
    else
    {
        ImGui::TextColored(theme::ERROR_TEXT, "%s", log_.loadError.c_str());
        ImGui::TextWrapped("Run the Vivado simulation first. The log is written to "
                           "<project>.sim/sim_1/behav/xsim/cache_log.jsonl. Paste that path above and press Load.");
    }

    ImGui::End();
}

void App::handleKeys(double now)
{
    if(ImGui::GetIO().WantTextInput)
        return;
    if(ImGui::IsKeyPressed(ImGuiKey_RightArrow))
        player_.next();
    if(ImGui::IsKeyPressed(ImGuiKey_LeftArrow))
        player_.previous();
    if(ImGui::IsKeyPressed(ImGuiKey_Space))
        player_.togglePlay(now);
}

void App::drawToolbar(double now)
{
    ImGui::SetNextItemWidth(360);
    ImGui::InputText("##path", path_, sizeof(path_));
    ImGui::SameLine();
    if(ImGui::Button("Load"))
        load();

    ImGui::SameLine();
    ImGui::TextDisabled("|");
    ImGui::SameLine();
    if(ImGui::Button("|<"))
        player_.first();
    ImGui::SameLine();
    if(ImGui::Button("< Prev"))
        player_.previous();
    ImGui::SameLine();
    if(ImGui::Button(player_.isPlaying() ? "Pause" : "Play", ImVec2(70, 0)))
        player_.togglePlay(now);
    ImGui::SameLine();
    if(ImGui::Button("Next >"))
        player_.next();
    ImGui::SameLine();
    if(ImGui::Button(">|"))
        player_.last();
    ImGui::SameLine();
    ImGui::SetNextItemWidth(140);
    ImGui::SliderFloat("steps/s", &player_.stepsPerSecond, 0.5f, 10.0f, "%.1f");

    if(!log_.ok())
        return;
    ImGui::SameLine();
    ImGui::TextDisabled("|");
    ImGui::SameLine();
    ImGui::Text("Step %d / %d    t = %d ns    %d sets x %d ways, %d B lines, %s", player_.current() + 1,
                player_.count(), log_.steps[player_.current()].time, log_.sets, log_.ways, log_.lineSize,
                log_.policy.c_str());
}

void App::drawSidebar()
{
    ImGui::BeginChild("sidebar", ImVec2(380, 0), ImGuiChildFlags_Borders);
    drawScenarioList(log_.steps[player_.current()]);
    ImGui::Separator();
    drawStepList();
    ImGui::EndChild();
}

void App::drawScenarioList(const Step& current)
{
    ImGui::TextDisabled("SCENARIOS");
    for(const Scenario& sc : log_.scenarios)
    {
        if(ImGui::Selectable(sc.name.c_str(), current.scenarioName == sc.name))
            player_.goTo(sc.firstStep);
    }

    if(log_.errors == 0)
        ImGui::TextColored(theme::OK_TEXT, "All checks passed");
    else if(log_.errors > 0)
        ImGui::TextColored(theme::ERROR_TEXT, "%d check(s) failed", log_.errors);
}

void App::drawStepList()
{
    ImGui::TextDisabled("STEPS");
    ImGui::BeginChild("steps");
    bool scroll = player_.takeScrollRequest();

    for(int i = 0; i < (int)log_.steps.size(); i++)
    {
        const Step& step = log_.steps[i];
        bool isScenario = step.type == "scenario";
        ImGui::PushID(i);
        if(isScenario)
            ImGui::PushStyleColor(ImGuiCol_Text, theme::SCENARIO_TEXT);

        char time[32];
        std::snprintf(time, sizeof(time), "%5d ns", step.time);
        if(ImGui::Selectable(time, i == player_.current(), ImGuiSelectableFlags_SpanAllColumns))
            player_.goTo(i);
        ImGui::SameLine(90);
        ImGui::TextUnformatted(briefEvent(step).c_str());

        if(isScenario)
            ImGui::PopStyleColor();
        if(scroll && i == player_.current())
            ImGui::SetScrollHereY(0.4f);
        ImGui::PopID();
    }
    ImGui::EndChild();
}

void App::drawStepView()
{
    int index = player_.current();
    const Step& step = log_.steps[index];
    const Step* previous = index > 0 ? &log_.steps[index - 1] : nullptr;

    ImGui::BeginChild("view", ImVec2(0, 0), ImGuiChildFlags_Borders);

    if(!step.scenarioName.empty())
        ImGui::TextColored(theme::SCENARIO_TEXT, "%s", step.scenarioName.c_str());
    drawSystemDiagram(step, ImGui::GetContentRegionAvail().x);

    ImGui::BeginChild("description", ImVec2(0, 110), ImGuiChildFlags_Borders);
    ImGui::TextWrapped("%s", step.title.c_str());
    for(const std::string& d : step.details)
        ImGui::BulletText("%s", d.c_str());
    ImGui::EndChild();

    drawCachePanels(step, previous);
    drawMemoryTable(step, log_.wordsPerLine());

    ImGui::EndChild();
}

void App::drawCachePanels(const Step& step, const Step* previous)
{
    float half = (ImGui::GetContentRegionAvail().x - ImGui::GetStyle().ItemSpacing.x) / 2;
    for(int c = 0; c < 2; c++)
    {
        if(c == 1)
            ImGui::SameLine();
        ImGui::PushID(c);
        ImGui::BeginChild("cache", ImVec2(half, 260), ImGuiChildFlags_Borders);

        ImGui::Text("Cache %d", c);
        const json& last = step.lastCpu[c];
        if(!last.is_null())
        {
            ImGui::SameLine();
            ImGui::TextDisabled("   last access: %s %s %s (%s)", last.value("op", "").c_str(),
                                shortHex(last.value("addr", "")).c_str(), shortHex(last.value("value", "")).c_str(),
                                last.value("result", "").c_str());
        }
        drawCacheTable("table", step.cache[c], previous ? &previous->cache[c] : nullptr);

        ImGui::EndChild();
        ImGui::PopID();
    }
}
