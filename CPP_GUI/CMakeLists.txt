cmake_minimum_required(VERSION 3.20)
project(cache_viewer C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GLFW_INSTALL OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_WAYLAND OFF CACHE BOOL "" FORCE)

FetchContent_Declare(glfw
  GIT_REPOSITORY https://github.com/glfw/glfw.git
  GIT_TAG 3.4
  GIT_SHALLOW TRUE)

FetchContent_Declare(imgui
  GIT_REPOSITORY https://github.com/ocornut/imgui.git
  GIT_TAG v1.91.5
  GIT_SHALLOW TRUE)

FetchContent_Declare(json
  URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

FetchContent_MakeAvailable(glfw imgui json)

find_package(OpenGL REQUIRED)

add_executable(cache_viewer
  src/main.cpp
  src/app.cpp
  src/log_model.cpp
  src/describe.cpp
  src/player.cpp
  src/diagram.cpp
  src/tables.cpp
  src/theme.cpp
  ${imgui_SOURCE_DIR}/imgui.cpp
  ${imgui_SOURCE_DIR}/imgui_draw.cpp
  ${imgui_SOURCE_DIR}/imgui_tables.cpp
  ${imgui_SOURCE_DIR}/imgui_widgets.cpp
  ${imgui_SOURCE_DIR}/backends/imgui_impl_glfw.cpp
  ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp)

target_include_directories(cache_viewer PRIVATE
  src
  ${imgui_SOURCE_DIR}
  ${imgui_SOURCE_DIR}/backends)

target_link_libraries(cache_viewer PRIVATE glfw OpenGL::GL nlohmann_json::nlohmann_json)

if(MSVC)
  set_property(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT cache_viewer)
endif()
