#pragma once

namespace AppIdentity {
// 系统标识由 CMake 唯一配置，应用包、缓存与凭据使用同一命名空间。
inline constexpr const char *Id = RHINE_APPLICATION_ID;
inline constexpr const char *Organization = "MikuTetoMusicLocal";
inline constexpr const char *DisplayName = "Miku Teto Music";
inline constexpr const char *PlayerPreference = "local.mikuteto.music.activate-player";
}
