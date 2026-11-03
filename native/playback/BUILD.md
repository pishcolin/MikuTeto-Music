# Mixed playback service

This directory contains the native playback subset of Rhine Music Database **v1.3.0**,
with a shared QQ/NetEase queue. Its upstream MIT license is in the source archive root.
The Qt Quick frontend and Node provider worker remain separate processes.

Use an x64 MSVC 2022 developer shell, Windows SDK, CMake 3.24+, and the Qt 6.12 MSVC kit
with Qt Base and Qt Multimedia. These are build dependencies only; never bundle the SDK.

```powershell
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=C:/Qt/6.12.0/msvc2022_64
cmake --build build
```

Copy `build/RhinePlaybackService.exe` into a separate copy of the official v1.3.0 runtime,
retaining its DLLs, plugins, resources and licenses. Use `worker-dual.cjs` as the runtime's
`resources/MusicBridge/worker.cjs`. The Python bridge requires the `mixedQueue` capability
in the service snapshot and will report an older service instead of silently resetting queues.

Native changes: select audio API and stream validation from the current track; keep catalog
selection independent; persist per-platform quality; preserve the queue on logout; restore
mixed sessions; use normalized provider+ID identities for queue indices. Credentials remain
owned by Host and Windows DPAPI. The shared queue still runs entirely in the native service,
including end-of-track transitions and system media buttons.

`-DMIKU_PLAYBACK_CHECKS=ON` also builds `MikuMixedQueueChecks`. Run it with an absolute path
to a short silent WAV file to check source routing, deferred songs, automatic mixed transitions
and restore without accessing accounts or provider servers.
