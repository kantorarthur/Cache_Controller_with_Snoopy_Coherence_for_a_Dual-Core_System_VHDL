#include "theme.hpp"

#include <fstream>

namespace theme
{

void apply()
{
    ImGui::StyleColorsDark();
    ImGuiStyle& style = ImGui::GetStyle();
    style.WindowRounding = 0.0f;
    style.FrameRounding = 4.0f;
    style.ChildRounding = 6.0f;
}

void loadFont()
{
    const char* candidates[] = {
        "C:\\Windows\\Fonts\\segoeui.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
    };
    ImGuiIO& io = ImGui::GetIO();
    for(const char* path : candidates)
    {
        if(std::ifstream(path).good())
        {
            io.Fonts->AddFontFromFileTTF(path, 16.0f);
            return;
        }
    }
    io.Fonts->AddFontDefault();
}

} // namespace theme
