#pragma once

#include "imgui.h"
#include <string>

namespace theme
{

inline const ImU32 STATE_M = IM_COL32(214, 79, 79, 255);
inline const ImU32 STATE_S = IM_COL32(72, 168, 96, 255);
inline const ImU32 STATE_I = IM_COL32(110, 110, 118, 255);
inline const ImU32 ACCENT = IM_COL32(66, 150, 250, 255);
inline const ImU32 IDLE = IM_COL32(90, 90, 100, 255);
inline const ImU32 BOX = IM_COL32(40, 42, 50, 255);
inline const ImU32 TEXT = IM_COL32(230, 230, 235, 255);
inline const ImU32 TEXT_DIM = IM_COL32(160, 160, 170, 255);
inline const ImU32 CHANGED_ROW = IM_COL32(230, 190, 60, 70);

inline const ImVec4 SCENARIO_TEXT(0.55f, 0.75f, 1.0f, 1.0f);
inline const ImVec4 OK_TEXT(0.4f, 0.8f, 0.5f, 1.0f);
inline const ImVec4 ERROR_TEXT(1.0f, 0.4f, 0.4f, 1.0f);

inline ImU32 stateColor(const std::string& state)
{
    if(state == "M")
        return STATE_M;
    if(state == "S")
        return STATE_S;
    return STATE_I;
}

void apply();
void loadFont();

} // namespace theme
