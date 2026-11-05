#include "app.hpp"
#include "theme.hpp"

#include <GLFW/glfw3.h>
#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_opengl3.h"

#include <cstdlib>
#include <string>

static GLFWwindow* createWindow()
{
    if(!glfwInit())
        return nullptr;
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
    GLFWwindow* window = glfwCreateWindow(1440, 920, "MSI Cache Coherence Viewer", nullptr, nullptr);
    if(!window)
        return nullptr;
    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);
    return window;
}

static void initImGui(GLFWwindow* window)
{
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::GetIO().IniFilename = nullptr;
    theme::loadFont();
    theme::apply();
    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL3_Init("#version 130");
}

static void renderFrame(GLFWwindow* window)
{
    ImGui::Render();
    int w, h;
    glfwGetFramebufferSize(window, &w, &h);
    glViewport(0, 0, w, h);
    glClearColor(0.08f, 0.08f, 0.1f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
    glfwSwapBuffers(window);
}

static void shutdown(GLFWwindow* window)
{
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    glfwDestroyWindow(window);
    glfwTerminate();
}

int main(int argc, char** argv)
{
    GLFWwindow* window = createWindow();
    if(!window)
        return 1;
    initImGui(window);

    App app(argc > 1 ? argv[1] : "cache_log.jsonl");
    if(argc > 2)
        app.jumpTo(std::atoi(argv[2]));

    while(!glfwWindowShouldClose(window))
    {
        glfwPollEvents();
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();
        app.frame(glfwGetTime());
        renderFrame(window);
    }

    shutdown(window);
    return 0;
}
