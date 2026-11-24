#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <deque>
#include <utility>

#include "activation.h"
#include "include/flutter_linkme_sdk_windows/flutter_linkme_sdk_windows_plugin_c_api.h"

namespace {
constexpr wchar_t kWindowClass[] = L"LinkMeActivation.3311ad98-47ef-4dc3-b1bb-ceba510524b2";
constexpr ULONG_PTR kActivationMessage = 0x4c4d0001;
constexpr size_t kMaxUriBytes = 2048;
constexpr size_t kMaxPending = 32;

struct PrimaryInstance {
  HANDLE mutex = nullptr;
  HWND window = nullptr;
  std::string initial_uri;
  std::deque<std::string> pending;
  std::function<void()> notify;
};

PrimaryInstance instance;

std::optional<std::string> GetProtocolArgument() {
  int count = 0;
  wchar_t** arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  if (!arguments) return std::nullopt;
  const std::wstring value = count == 2 ? arguments[1] : L"";
  LocalFree(arguments);
  const size_t colon = value.find(L':');
  if (colon == std::wstring::npos || colon < 2 ||
      value.find_first_not_of(L"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
                              L"0123456789+.-", 0) < colon) {
    return std::nullopt;
  }
  if (value.size() > kMaxUriBytes) return std::string("invalid");

  const int length = static_cast<int>(value.size());
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                      value.data(), length, nullptr, 0,
                                      nullptr, nullptr);
  if (size <= 0 || static_cast<size_t>(size) > kMaxUriBytes) {
    return std::string("invalid");
  }
  std::string result(size, '\0');
  if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                           length, result.data(), size, nullptr, nullptr)) {
    return std::string("invalid");
  }
  return result;
}

LRESULT CALLBACK ActivationWindowProc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  if (message != WM_COPYDATA) {
    return DefWindowProcW(window, message, wparam, lparam);
  }
  const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
  if (!data || data->dwData != kActivationMessage ||
      data->cbData > kMaxUriBytes || (data->cbData && !data->lpData)) {
    return FALSE;
  }
  if (data->cbData) {
    // Local protocol activations are untrusted. Dart validates the envelope
    // and requires the app-scoped claim before exposing any routing data.
    const std::string uri(static_cast<const char*>(data->lpData), data->cbData);
    if (uri.find('\0') != std::string::npos) return FALSE;
    if (std::find(instance.pending.begin(), instance.pending.end(), uri) ==
        instance.pending.end()) {
      if (instance.pending.size() >= kMaxPending) return FALSE;
      instance.pending.push_back(uri);
    }
  }
  if (instance.notify) instance.notify();
  return TRUE;
}

HWND CreateActivationWindow(const wchar_t* identity) {
  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = ActivationWindowProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.lpszClassName = kWindowClass;
  if (!RegisterClassW(&window_class)) return nullptr;
  return CreateWindowExW(0, kWindowClass, identity, 0, 0, 0, 0, 0,
                         HWND_MESSAGE, nullptr, window_class.hInstance,
                         nullptr);
}
}  // namespace

LinkMeWindowsInstanceResult LinkMeStartWindowsInstance(const wchar_t* identity) {
  if (!identity || !*identity || instance.mutex) return kLinkMeActivationFailed;
  const std::wstring name = L"Local\\LinkMeActivation." + std::wstring(identity);
  const HANDLE mutex = CreateMutexW(nullptr, FALSE, name.c_str());
  if (!mutex) return kLinkMeActivationFailed;
  const std::string uri = GetProtocolArgument().value_or("");

  // The primary may still be starting or in the process of closing. Never
  // start another window merely because it has not created its receiver yet.
  const ULONGLONG deadline = GetTickCount64() + 5000;
  do {
    const DWORD wait = WaitForSingleObject(mutex, 0);
    if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
      instance.window = CreateActivationWindow(identity);
      if (!instance.window) {
        ReleaseMutex(mutex);
        CloseHandle(mutex);
        return kLinkMeActivationFailed;
      }
      instance.mutex = mutex;  // Owned for the lifetime of this GUI thread.
      instance.initial_uri = uri;
      return kLinkMePrimary;
    }
    if (wait != WAIT_TIMEOUT) break;

    const HWND window = FindWindowExW(HWND_MESSAGE, nullptr, kWindowClass, identity);
    if (window) {
      COPYDATASTRUCT data = {kActivationMessage, static_cast<DWORD>(uri.size()),
                             const_cast<char*>(uri.data())};
      DWORD_PTR acknowledged = 0;
      if (SendMessageTimeoutW(window, WM_COPYDATA, 0,
                              reinterpret_cast<LPARAM>(&data),
                              SMTO_ABORTIFHUNG | SMTO_BLOCK, 1000,
                              &acknowledged) && acknowledged == TRUE) {
        CloseHandle(mutex);
        return kLinkMeForwarded;
      }
    }
    Sleep(50);
  } while (GetTickCount64() < deadline);

  CloseHandle(mutex);
  return kLinkMeActivationFailed;
}

bool LinkMeHasWindowsProtocolArgument() {
  return GetProtocolArgument().has_value();
}

namespace linkme {
bool ActivationAvailable() { return instance.window != nullptr; }

std::string InitialUri() { return instance.initial_uri; }

std::optional<std::string> TakeNextUri() {
  if (instance.pending.empty()) return std::nullopt;
  auto uri = std::move(instance.pending.front());
  instance.pending.pop_front();
  return uri;
}

void SetActivationCallback(std::function<void()> callback) {
  instance.notify = std::move(callback);
}
}  // namespace linkme
