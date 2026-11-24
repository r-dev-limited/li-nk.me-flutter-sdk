#ifndef FLUTTER_PLUGIN_FLUTTER_LINKME_SDK_WINDOWS_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_FLUTTER_LINKME_SDK_WINDOWS_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>
#include <wchar.h>

#if defined(FLUTTER_PLUGIN_IMPL)
#define LINKME_WINDOWS_EXPORT __declspec(dllexport)
#else
#define LINKME_WINDOWS_EXPORT __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef enum LinkMeWindowsInstanceResult {
  kLinkMePrimary,
  kLinkMeForwarded,
  kLinkMeActivationFailed,
} LinkMeWindowsInstanceResult;

// Call on the GUI thread before creating the Flutter engine. Use a unique,
// stable identity for each installed application and environment.
LINKME_WINDOWS_EXPORT LinkMeWindowsInstanceResult
LinkMeStartWindowsInstance(const wchar_t* identity);

// True if the command line contains a protocol argument handled by LinkMe.
// Hosts should keep that argument out of general-purpose Dart launch args.
LINKME_WINDOWS_EXPORT bool LinkMeHasWindowsProtocolArgument();

LINKME_WINDOWS_EXPORT void FlutterLinkmeSdkWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_PLUGIN_FLUTTER_LINKME_SDK_WINDOWS_PLUGIN_C_API_H_
