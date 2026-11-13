#include "camera_frame_relay.h"

#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>

namespace {
std::atomic<PreTraVideoOutputListener> g_listener{nullptr};
std::atomic<PreTraMetricsListener> g_metrics_listener{nullptr};
std::atomic<PreTraValidationListener> g_validation_listener{nullptr};
std::atomic<PreTraErrorListener> g_error_listener{nullptr};
std::atomic<int64_t> g_last_frame_us{0};

char* copy_string(const char* value) {
  if (value == nullptr) return nullptr;
  size_t length = 0;
  while (length < 4096 && value[length] != '\0') ++length;
  auto* copy = static_cast<char*>(std::malloc(length + 1));
  if (copy == nullptr) return nullptr;
  std::memcpy(copy, value, length);
  copy[length] = '\0';
  return copy;
}
}

extern "C" __declspec(dllexport) void __cdecl
pretra_set_metrics_listener(PreTraMetricsListener listener) {
  g_metrics_listener.store(listener, std::memory_order_release);
}

extern "C" __declspec(dllexport) void __cdecl
pretra_set_validation_listener(PreTraValidationListener listener) {
  g_validation_listener.store(listener, std::memory_order_release);
}

extern "C" __declspec(dllexport) void __cdecl
pretra_set_error_listener(PreTraErrorListener listener) {
  g_error_listener.store(listener, std::memory_order_release);
}

extern "C" __declspec(dllexport) void __cdecl pretra_metrics_relay(
    uintptr_t handle, const uint8_t* data, int32_t length,
    int64_t timestamp_us) {
  const auto listener = g_metrics_listener.load(std::memory_order_acquire);
  if (listener == nullptr || data == nullptr || length <= 0 ||
      length > 64 * 1024 * 1024) {
    return;
  }
  auto* copy = static_cast<uint8_t*>(std::malloc(static_cast<size_t>(length)));
  if (copy == nullptr) return;
  std::memcpy(copy, data, static_cast<size_t>(length));
  listener(handle, copy, length, timestamp_us);
}

extern "C" __declspec(dllexport) void __cdecl pretra_validation_relay(
    uintptr_t handle, int32_t code, const char* hint, int64_t timestamp_us) {
  const auto listener = g_validation_listener.load(std::memory_order_acquire);
  if (listener == nullptr) return;
  char* copy = copy_string(hint);
  if (hint != nullptr && copy == nullptr) return;
  listener(handle, code, copy, timestamp_us);
}

extern "C" __declspec(dllexport) void __cdecl pretra_error_relay(
    uintptr_t handle, int32_t code, const char* message, int32_t retryable) {
  const auto listener = g_error_listener.load(std::memory_order_acquire);
  if (listener == nullptr) return;
  char* copy = copy_string(message);
  if (message != nullptr && copy == nullptr) return;
  listener(handle, code, copy, retryable);
}

extern "C" __declspec(dllexport) void __cdecl
pretra_set_video_output_listener(PreTraVideoOutputListener listener) {
  g_listener.store(listener, std::memory_order_release);
}

extern "C" __declspec(dllexport) void __cdecl
pretra_free_video_frame(const uint8_t* data) {
  std::free(const_cast<uint8_t*>(data));
}

extern "C" __declspec(dllexport) void __cdecl pretra_video_output_relay(
    uintptr_t handle,
    const uint8_t* data,
    int32_t width,
    int32_t height,
    int32_t stride_bytes,
    int32_t pixel_format,
    int64_t timestamp_us) {
  const auto listener = g_listener.load(std::memory_order_acquire);
  if (listener == nullptr || data == nullptr || width <= 0 || height <= 0 ||
      width > 4096 || height > 4096 || stride_bytes <= 0) {
    return;
  }

  // Support packed RGB/BGR/RGBA/BGRA and NV12/NV21 output. Other formats are
  // skipped instead of risking an invalid buffer-size calculation.
  const int32_t channels =
      (pixel_format == 0 || pixel_format == 1) ? 3 :
      (pixel_format == 2 || pixel_format == 3) ? 4 : 1;
  const int32_t minimum_stride = (pixel_format == 4 || pixel_format == 5)
                                    ? ((width + 1) / 2) * 2
                                    : width * channels;
  if (pixel_format < 0 || pixel_format > 5 ||
      stride_bytes < minimum_stride) {
    return;
  }
  size_t byte_length = static_cast<size_t>(stride_bytes) * height;
  if (pixel_format == 4 || pixel_format == 5) {
    byte_length += static_cast<size_t>(stride_bytes) * ((height + 1) / 2);
  }
  if (byte_length == 0 || byte_length > 64u * 1024u * 1024u) return;

  // Native output is borrowed only for the SDK callback's duration. Relay a
  // bounded-rate owned copy so Dart's asynchronous listener never retains a
  // pointer into SDK memory.
  const auto now = std::chrono::duration_cast<std::chrono::microseconds>(
                       std::chrono::steady_clock::now().time_since_epoch())
                       .count();
  int64_t previous = g_last_frame_us.load(std::memory_order_relaxed);
  while (now - previous >= 66000) {
    if (g_last_frame_us.compare_exchange_weak(previous, now,
                                              std::memory_order_relaxed)) {
      auto* owned = static_cast<uint8_t*>(std::malloc(byte_length));
      if (owned == nullptr) return;
      std::memcpy(owned, data, byte_length);
      listener(handle, owned, width, height, stride_bytes, pixel_format,
               timestamp_us);
      return;
    }
  }
}
