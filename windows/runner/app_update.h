#ifndef RUNNER_APP_UPDATE_H_
#define RUNNER_APP_UPDATE_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateAppUpdateChannel(flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_APP_UPDATE_H_
