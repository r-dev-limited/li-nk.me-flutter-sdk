#include <windows.h>
#include <shellapi.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <utility>

#include "activation.h"
#include "include/flutter_linkme_sdk_windows/flutter_linkme_sdk_windows_plugin_c_api.h"

namespace {
using flutter::EncodableValue;
using Channel = flutter::MethodChannel<EncodableValue>;

bool OpenBrowser(const EncodableValue* argument) {
  const auto* url = argument ? std::get_if<std::string>(argument) : nullptr;
  if (!url || url->rfind("https://", 0) != 0 ||
      url->find('\0') != std::string::npos) {
    return false;
  }
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                      url->c_str(), -1, nullptr, 0);
  if (size <= 0) return false;
  std::wstring wide_url(size, L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url->c_str(), -1,
                           wide_url.data(), size)) {
    return false;
  }
  const auto result = ShellExecuteW(nullptr, L"open", wide_url.c_str(), nullptr,
                                    nullptr, SW_SHOWNORMAL);
  return reinterpret_cast<INT_PTR>(result) > 32;
}

class WindowsPlugin : public flutter::Plugin {
 public:
  explicit WindowsPlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar),
        channel_(registrar->messenger(), "me.link/flutter_linkme_sdk_windows",
                 &flutter::StandardMethodCodec::GetInstance()) {
    channel_.SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "isAvailable") {
        result->Success(EncodableValue(linkme::ActivationAvailable()));
      } else if (call.method_name() == "getInitialUri") {
        const std::string uri = linkme::InitialUri();
        result->Success(uri.empty() ? EncodableValue() : EncodableValue(uri));
      } else if (call.method_name() == "takeNextUri") {
        const auto uri = linkme::TakeNextUri();
        result->Success(uri ? EncodableValue(*uri) : EncodableValue());
      } else if (call.method_name() == "openBrowser") {
        result->Success(EncodableValue(OpenBrowser(call.arguments())));
      } else {
        result->NotImplemented();
      }
    });

    linkme::SetActivationCallback([this]() {
      if (auto* view = registrar_->GetView()) {
        const HWND window = GetAncestor(view->GetNativeWindow(), GA_ROOT);
        if (window) {
          if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
          SetForegroundWindow(window);
        }
      }
      channel_.InvokeMethod("activationsAvailable", nullptr);
    });
  }

  ~WindowsPlugin() override {
    linkme::SetActivationCallback({});
    channel_.SetMethodCallHandler(nullptr);
  }

 private:
  flutter::PluginRegistrarWindows* registrar_;
  Channel channel_;
};
}  // namespace

void FlutterLinkmeSdkWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows_registrar->AddPlugin(std::make_unique<WindowsPlugin>(windows_registrar));
}
