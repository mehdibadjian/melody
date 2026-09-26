import 'dart:typed_data';

import 'package:melody_app/domain/acoustic/pcm_decoder.dart';
import 'package:test/test.dart';

/// Encodes mono float samples in [-1, 1] as 16-bit little-endian PCM.
Uint8List pcm16(List<double> samples) {
  final out = Uint8List(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    var v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    out[i * 2] = v & 0xFF; // low byte
    out[(i * 2) + 1] = (v >> 8) & 0xFF; // high byte
  }
  return out;
}

void main() {
  group('PcmDecoder (16-bit little-endian mono)', () {
    test('decodes silence to zeros', () {
      final decoder = PcmDecoder();
      expect(decoder.push(pcm16([0, 0, 0])), [0.0, 0.0, 0.0]);
    });

    test('decodes empty input to empty output', () {
      expect(PcmDecoder().push(Uint8List(0)), isEmpty);
    });

    test('maps full-scale negative to -1.0', () {
      final bytes = Uint8List.fromList([0x00, 0x80]); // 0x8000 = -32768
      expect(PcmDecoder().push(bytes).single, closeTo(-1.0, 1e-4));
    });

    test('maps near full-scale positive to ~+1.0', () {
      final bytes = Uint8List.fromList([0xFF, 0x7F]); // 0x7FFF = 32767
      expect(PcmDecoder().push(bytes).single, closeTo(1.0, 1e-3));
    });

    test('decodes little-endian byte order (low byte first)', () {
      // 0x0001 -> low=0x01, high=0x00 => value 1 => 1/32768
      final bytes = Uint8List.fromList([0x01, 0x00]);
      expect(PcmDecoder().push(bytes).single, closeTo(1 / 32768, 1e-6));
    });

    test('round-trips a sine wave within quantisation error', () {
      final sine = [
        for (var i = 0; i < 64; i++) (i * 0.1).remainder(2.0) - 1.0
      ];
      final decoded = PcmDecoder().push(pcm16(sine));
      expect(decoded, hasLength(64));
      for (var i = 0; i < sine.length; i++) {
        expect(decoded[i], closeTo(sine[i], 1e-3));
      }
    });

    test('carries an odd trailing byte into the next chunk', () {
      final decoder = PcmDecoder();
      final full = pcm16([0.5, -0.25, 0.125]); // 6 bytes
      // Feed in 3 + 3 so a sample straddles the chunk boundary.
      final first = decoder.push(Uint8List.sublistView(full, 0, 3));
      final second = decoder.push(Uint8List.sublistView(full, 3, 6));
      final combined = [...first, ...second];
      expect(combined, hasLength(3));
      expect(combined[0], closeTo(0.5, 1e-3));
      expect(combined[1], closeTo(-0.25, 1e-3));
      expect(combined[2], closeTo(0.125, 1e-3));
    });

    test('a lone odd byte produces no sample until its partner arrives', () {
      final decoder = PcmDecoder();
      expect(decoder.push(Uint8List.fromList([0x00])), isEmpty);
      expect(decoder.push(Uint8List.fromList([0x40])), [closeTo(0.5, 1e-2)]);
    });
  });
}
