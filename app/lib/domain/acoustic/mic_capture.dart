import 'dart:typed_data';

/// Platform-agnostic microphone capture contract.
///
/// This is the seam that keeps the device-only code tiny and the coaching
/// pipeline testable: [AcousticPracticeNotifier] and the practice screen depend
/// on this interface, so CI can inject a fake capture that emits synthetic PCM
/// and exercise the full detect→debounce→coach path without a microphone. The
/// only untestable implementation is the thin `record`-plugin adapter
/// (`platform/record_mic_capture.dart`).
abstract interface class MicCapture {
  /// Whether the app may record audio. Returns false (never throws) when the
  /// permission is denied or unsupported on the platform.
  Future<bool> hasPermission();

  /// Begins capturing raw 16-bit little-endian mono PCM and returns the byte
  /// stream. Must only be called after [hasPermission] is true.
  Future<Stream<Uint8List>> start();

  /// Stops an in-progress capture. Safe to call when not capturing.
  Future<void> stop();

  /// Releases the underlying recorder resources.
  Future<void> dispose();
}
