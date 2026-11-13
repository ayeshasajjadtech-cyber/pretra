#pragma once

#include <cstdint>

extern "C" {

using PreTraVideoOutputListener = void(__cdecl*)(
    uintptr_t handle,
    const uint8_t* data,
    int32_t width,
    int32_t height,
    int32_t stride_bytes,
    int32_t pixel_format,
    int64_t timestamp_us);
using PreTraMetricsListener = void(__cdecl*)(
    uintptr_t handle, const uint8_t* data, int32_t length, int64_t timestamp_us);
using PreTraValidationListener = void(__cdecl*)(
    uintptr_t handle, int32_t code, const char* hint, int64_t timestamp_us);
using PreTraErrorListener = void(__cdecl*)(
    uintptr_t handle, int32_t code, const char* message, int32_t retryable);

__declspec(dllexport) void __cdecl pretra_set_metrics_listener(
    PreTraMetricsListener listener);
__declspec(dllexport) void __cdecl pretra_set_validation_listener(
    PreTraValidationListener listener);
__declspec(dllexport) void __cdecl pretra_set_error_listener(
    PreTraErrorListener listener);

__declspec(dllexport) void __cdecl pretra_metrics_relay(
    uintptr_t handle, const uint8_t* data, int32_t length, int64_t timestamp_us);
__declspec(dllexport) void __cdecl pretra_validation_relay(
    uintptr_t handle, int32_t code, const char* hint, int64_t timestamp_us);
__declspec(dllexport) void __cdecl pretra_error_relay(
    uintptr_t handle, int32_t code, const char* message, int32_t retryable);

__declspec(dllexport) void __cdecl pretra_set_video_output_listener(
    PreTraVideoOutputListener listener);

__declspec(dllexport) void __cdecl pretra_free_video_frame(
    const uint8_t* data);

__declspec(dllexport) void __cdecl pretra_video_output_relay(
    uintptr_t handle,
    const uint8_t* data,
    int32_t width,
    int32_t height,
    int32_t stride_bytes,
    int32_t pixel_format,
    int64_t timestamp_us);

}
