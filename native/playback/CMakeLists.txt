cmake_minimum_required(VERSION 3.24)
project(MikuMixedPlayback VERSION 1.0.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 6.12 REQUIRED COMPONENTS Core Gui Network Concurrent Multimedia)
add_library(MikuPlaybackCore STATIC
    AppUpdater.cpp AppStorage.cpp AudioPlayer.cpp HttpAudioStream.cpp
    PlaybackDiagnostics.cpp PlaybackConnection.cpp Host.cpp MusicApi.cpp
    MusicPlayer.cpp LyricsController.cpp Platform.cpp PlatformWindows.cpp
    qrcodegen.cpp)
target_include_directories(MikuPlaybackCore PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(MikuPlaybackCore PUBLIC RHINE_APPLICATION_ID="local.mikuteto.music"
    RHINE_VERSION="1.0.0" RHINE_RELEASE_BUILD=0)
target_compile_options(MikuPlaybackCore PUBLIC /utf-8 /permissive-)
target_link_libraries(MikuPlaybackCore PUBLIC Qt6::Core Qt6::Gui Qt6::Network
    Qt6::Concurrent Qt6::Multimedia crypt32 shell32 user32 windowsapp runtimeobject)
qt_add_executable(RhinePlaybackService WIN32 PlaybackService.cpp InterfaceSession.cpp playback_main.cpp)
target_link_libraries(RhinePlaybackService PRIVATE MikuPlaybackCore)
option(MIKU_PLAYBACK_CHECKS "Build deterministic mixed playback checks" OFF)
if(MIKU_PLAYBACK_CHECKS)
    qt_add_executable(MikuMixedQueueChecks MixedQueueChecks.cpp)
    target_link_libraries(MikuMixedQueueChecks PRIVATE MikuPlaybackCore)
endif()
