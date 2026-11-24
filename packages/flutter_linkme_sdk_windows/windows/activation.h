#ifndef FLUTTER_PLUGIN_LINKME_WINDOWS_ACTIVATION_H_
#define FLUTTER_PLUGIN_LINKME_WINDOWS_ACTIVATION_H_

#include <functional>
#include <string>
#include <optional>

namespace linkme {
bool ActivationAvailable();
std::string InitialUri();
std::optional<std::string> TakeNextUri();
void SetActivationCallback(std::function<void()> callback);
}  // namespace linkme

#endif
