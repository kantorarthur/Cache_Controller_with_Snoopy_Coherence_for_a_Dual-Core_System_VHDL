#pragma once

#include "log_model.hpp"
#include "player.hpp"

#include <string>

class App
{
  public:
    explicit App(const std::string& logPath);

    void frame(double now);
    void jumpTo(int step)
    {
        player_.goTo(step);
    }

  private:
    void load();
    void handleKeys(double now);
    void drawToolbar(double now);
    void drawSidebar();
    void drawScenarioList(const Step& current);
    void drawStepList();
    void drawStepView();
    void drawCachePanels(const Step& step, const Step* previous);

    char path_[1024] = {};
    SimLog log_;
    Player player_;
};
