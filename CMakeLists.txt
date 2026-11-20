cmake_minimum_required(VERSION 3.22)
project(Flowen VERSION 0.5.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
# One version for the window, notas-mcp and the About dialog.
add_compile_definitions(FLOWEN_VERSION="${PROJECT_VERSION}")
if(MSVC)
  add_compile_options(/utf-8 /W4)
endif()
find_package(Qt6 6.8 REQUIRED COMPONENTS Core Sql Gui Qml Quick QuickControls2 Svg)
add_library(notes_core STATIC src/core/contract.cpp src/core/store.cpp src/core/library.cpp src/core/inlines.cpp)
target_include_directories(notes_core PUBLIC src/core)
target_link_libraries(notes_core PUBLIC Qt6::Core Qt6::Sql)
add_executable(notas-mcp src/mcp/main.cpp)
target_link_libraries(notas-mcp PRIVATE notes_core)
set(EDITOR_SOURCES src/desktop/editor.cpp src/desktop/mcplink.cpp src/desktop/connectors.cpp src/desktop/writingassistant.cpp src/desktop/pagefile.cpp src/desktop/inlineeditor.cpp src/desktop/usagelog.cpp src/desktop/planlimits.cpp src/desktop/svgglyph.cpp)
# Flowen's symbols (design/identidad/iconografia), drawn by SvgGlyph.
file(GLOB GLYPH_FILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS assets/glyphs/*.svg)
qt_add_executable(flowen WIN32 src/desktop/main.cpp ${EDITOR_SOURCES})
target_link_libraries(flowen PRIVATE notes_core Qt6::Quick Qt6::QuickControls2 Qt6::Svg)
qt_add_resources(flowen glyphs PREFIX "/glyphs" BASE assets/glyphs FILES ${GLYPH_FILES})
qt_add_resources(flowen views PREFIX "/" FILES qml/Main.qml qml/qmldir qml/Theme.qml qml/UiButton.qml qml/BlockRow.qml
    qml/Glyph.qml qml/WorkspaceMenus.qml qml/WritingDialog.qml qml/PhotoBlock.qml qml/ConnectorsPage.qml qml/SelectionBubble.qml
    qml/AiComposer.qml qml/EngineSwitch.qml qml/AiProblem.qml qml/CommentCard.qml qml/CommentRail.qml qml/UsagePage.qml
    qml/PlanLimitsView.qml qml/UsageButton.qml qml/SlashMenu.qml
    qml/EmojiPicker.qml qml/PageIcon.qml qml/PageHeader.qml qml/PageCover.qml qml/PageMenu.qml
    qml/SidebarSection.qml qml/RecentCards.qml qml/EngineMark.qml qml/TemplateStrip.qml qml/AskPage.qml qml/UiMenu.qml qml/UiMenuItem.qml qml/UiMenuSeparator.qml qml/PageOutline.qml qml/Sidebar.qml
    qml/ViewSwitch.qml qml/PaperSheets.qml qml/PaperMenu.qml qml/HelpDialog.qml qml/AboutDialog.qml
    assets/brand/ao-lockup-white.png assets/brand/ao-lockup-ink.png
    assets/flowen-64.png assets/flowen-256.png)
# Windows file details (product, version, publisher) and the icon of both programs; the installer
# (FlowenInnoSetup.iss) reads the version from flowen.exe.
function(flowen_version_info target file description icon)
  set(RC_FILE "${file}")
  set(RC_DESCRIPTION "${description}")
  set(RC_ICON "")
  if(icon)
    set(RC_ICON "IDI_ICON1 ICON \"${CMAKE_CURRENT_SOURCE_DIR}/${icon}\"")
  endif()
  configure_file(assets/version.rc.in ${CMAKE_CURRENT_BINARY_DIR}/${target}.rc @ONLY)
  target_sources(${target} PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/${target}.rc)
endfunction()
if(WIN32)
  flowen_version_info(flowen flowen.exe "Flowen" assets/flowen.ico)
  flowen_version_info(notas-mcp notas-mcp.exe "Servidor MCP de Flowen" "")
endif()
include(CTest)
if(BUILD_TESTING)
  find_package(Python3 3.11 REQUIRED COMPONENTS Interpreter)
  find_package(Qt6 6.8 REQUIRED COMPONENTS Test)
  add_test(NAME contrato_mcp COMMAND Python3::Interpreter ${CMAKE_CURRENT_SOURCE_DIR}/tests/integration.py $<TARGET_FILE:notas-mcp>)
  add_executable(editor_test tests/editor_test.cpp ${EDITOR_SOURCES})
  target_include_directories(editor_test PRIVATE src/desktop)
  target_link_libraries(editor_test PRIVATE notes_core Qt6::Test Qt6::Quick Qt6::QuickControls2 Qt6::Svg)
  qt_add_resources(editor_test test_glyphs PREFIX "/glyphs" BASE assets/glyphs FILES ${GLYPH_FILES})
  target_compile_definitions(editor_test PRIVATE UI_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml")
  add_test(NAME editor_y_recuperacion COMMAND editor_test -platform offscreen)
  set_tests_properties(contrato_mcp editor_y_recuperacion PROPERTIES TIMEOUT 60)
  set_tests_properties(editor_y_recuperacion PROPERTIES ENVIRONMENT "QT_QUICK_BACKEND=software;QT_FORCE_STDERR_LOGGING=1")
  add_dependencies(editor_test notas-mcp)
  if(WIN32)
    get_target_property(QT_QMAKE Qt6::qmake IMPORTED_LOCATION)
    get_filename_component(QT_BIN "${QT_QMAKE}" DIRECTORY)
    set_tests_properties(contrato_mcp editor_y_recuperacion PROPERTIES
      ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:${QT_BIN}")
  endif()
endif()
