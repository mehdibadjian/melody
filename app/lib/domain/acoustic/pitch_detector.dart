import 'dart:math' as math;

/// Estimate of the fundamental frequency of an audio frame.
class PitchEstimate {
  const PitchEstimate({required this.frequencyHz, required this.clarity});

  /// Detected fundamental frequency in Hertz.
  final double frequencyHz;

  /// Confidence in 0..1 (NSDF peak value). Higher = cleaner, more periodic
  /// signal. Callers should gate on this to reject noise and transients.
  final double clarity;
}

/// A named pitch in scientific notation plus its tuning deviation.
class NoteName {
  const NoteName({required this.note, required this.cents});

  /// e.g. `C4`, `F#5` — matches the app's existing pitch vocabulary.
  final String note;

  /// Signed cents from the nearest equal-tempered note (-50..+50).
  final int cents;

  @override
  String toString() => '$note ${cents >= 0 ? '+' : ''}${cents}c';
}

const _noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B'
];

/// Maps a frequency to the nearest equal-tempered note name and its cents
/// offset. Returns null for non-physical frequencies.
NoteName? noteFromFrequency(double frequencyHz) {
  if (frequencyHz <= 0) return null;
  // MIDI note number: A4 = 440 Hz = MIDI 69.
  final midiFloat = 69 + 12 * (math.log(frequencyHz / 440) / math.ln2);
  final midi = midiFloat.round();
  final cents = ((midiFloat - midi) * 100).round();
  final octave = (midi ~/ 12) - 1;
  final name = _noteNames[((midi % 12) + 12) % 12];
  return NoteName(note: '$name$octave', cents: cents);
}

/// Time-domain pitch detector using the Normalized Square Difference
/// Function (NSDF, de Cheveigné & Kawahara 2002).
///
/// NSDF is chosen over raw autocorrelation because normalization suppresses
/// the sub-octave errors that make naive autocorrelation unreliable on
/// harmonic (musical) signals — exactly what an electric keyboard produces.
///
/// Pure Dart and allocation-light so it can run per audio frame; live capture
/// (microphone plugin, permissions, latency) is a separate concern layered on
/// top via the existing `InstrumentInput` contract.
class PitchDetector {
  PitchDetector({
    this.sampleRate = 22050,
    this.minFrequencyHz = 80,
    this.maxFrequencyHz = 1200,
    this.clarityThreshold = 0.7,
  });

  final int sampleRate;

  /// Lowest fundamental to look for. Below ~C2 is out of a child's keyboard
  /// range and dominated by room rumble.
  final double minFrequencyHz;

  /// Highest fundamental to look for. Above ~D6 is beyond the v1 content.
  final double maxFrequencyHz;

  /// Minimum NSDF peak value to accept a detection as voiced.
  final double clarityThreshold;

  /// Returns a [PitchEstimate] for [frame], or null when the frame is silent,
  /// too short, or not confidently periodic.
  PitchEstimate? detect(List<double> frame) {
    final w = frame.length;
    if (w < 2) return null;

    // Period range in samples for the frequency band of interest.
    final minTau = math.max(2, (sampleRate / maxFrequencyHz).floor());
    final maxTau = math.min(w - 1, (sampleRate / minFrequencyHz).ceil());
    if (maxTau <= minTau + 1) return null;

    // Reuse buffers across calls to avoid per-frame allocation churn.
    final nsdf = List<double>.filled(maxTau + 1, 0);

    // NSDF(τ) = 1 − d(τ)/(Φ(τ)+Φ'(τ)), where d(τ)=Σ(x[j]−x[j+τ])².
    // Result is in [−1, 1]: 1 = perfectly periodic at lag τ.
    for (var tau = minTau; tau <= maxTau; tau++) {
      var diff = 0.0;
      var e1 = 0.0;
      var e2 = 0.0;
      final limit = w - tau;
      for (var j = 0; j < limit; j++) {
        final a = frame[j];
        final b = frame[j + tau];
        final d = a - b;
        diff += d * d;
        e1 += a * a;
        e2 += b * b;
      }
      final norm = e1 + e2;
      nsdf[tau] = norm <= 0 ? 0 : 1 - diff / norm;
    }

    // Find the first NSDF peak that rises above the threshold and is a local
    // maximum. Searching from the smallest tau (highest frequency) and taking
    // the first strong peak avoids locking onto a sub-octave.
    var bestTau = -1;
    var bestVal = 0.0;
    for (var tau = minTau + 1; tau < maxTau; tau++) {
      final v = nsdf[tau];
      if (v <= clarityThreshold) continue;
      // local max?
      if (v < nsdf[tau - 1] || v < nsdf[tau + 1]) continue;
      bestVal = v;
      bestTau = tau;
      break; // first strong peak = highest-priority (shortest) period
    }
    if (bestTau < 0) return null;

    // Parabolic interpolation around the peak for sub-sample period accuracy.
    final refined = _parabolic(nsdf, bestTau);

    final frequency = sampleRate / refined;
    if (frequency < minFrequencyHz || frequency > maxFrequencyHz) return null;

    return PitchEstimate(
      frequencyHz: frequency,
      clarity: bestVal.clamp(0.0, 1.0),
    );
  }

  /// Parabolic (quadratic) interpolation of the true peak between samples.
  double _parabolic(List<double> nsdf, int tau) {
    final s0 = nsdf[tau - 1];
    final s1 = nsdf[tau];
    final s2 = nsdf[tau + 1];
    final denom = (2 * (2 * s1 - s2 - s0));
    if (denom.abs() < 1e-12) return tau.toDouble();
    final adjustment = (s2 - s0) / denom;
    return tau + adjustment;
  }
}
