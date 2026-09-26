import 'dart:typed_data';

/// Decodes raw 16-bit little-endian PCM byte chunks (what the `record`
/// plugin streams in `pcm16bits` mono mode) into float samples in [-1, 1],
/// the format [PitchDetector] consumes.
///
/// Mic chunks are arbitrary in size, so a 2-byte sample can straddle a chunk
/// boundary. The decoder carries that dangling byte across [push] calls so no
/// sample is ever split or dropped. Pure Dart, allocation-light, fully
/// unit-testable without a microphone.
class PcmDecoder {
  /// Holds at most one leftover byte between chunks.
  Uint8List? _carry;

  /// Decodes [chunk], returning the float samples it completes. Any odd
  /// trailing byte is retained for the next call.
  List<double> push(Uint8List chunk) {
    final carry = _carry;
    final Uint8List bytes;
    if (carry == null) {
      bytes = chunk;
    } else {
      bytes = Uint8List(carry.length + chunk.length)
        ..setRange(0, carry.length, carry)
        ..setRange(carry.length, carry.length + chunk.length, chunk);
      _carry = null;
    }

    final sampleCount = bytes.length ~/ 2;
    if (sampleCount == 0) {
      // Fewer than two bytes: keep a single dangling byte, drop nothing else.
      if (bytes.length == 1) _carry = Uint8List.fromList(bytes);
      return const [];
    }

    final samples = List<double>.filled(sampleCount, 0);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < sampleCount; i++) {
      // Signed 16-bit LE -> [-1, 1]. Divide by 32768 so -32768 maps to -1.0.
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }

    // Retain a trailing odd byte for the next chunk.
    if (bytes.length.isOdd) {
      _carry = Uint8List.fromList([bytes.last]);
    }
    return samples;
  }

  /// Discards any carried partial sample (e.g. on session restart).
  void reset() => _carry = null;
}
