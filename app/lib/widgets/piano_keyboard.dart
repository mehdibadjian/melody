import 'package:flutter/material.dart';

class PianoKeyboard extends StatelessWidget {
  const PianoKeyboard({
    super.key,
    required this.onNote,
    required this.targetNote,
    required this.height,
  });

  final void Function(String note) onNote;
  final String targetNote;
  final double height;

  static const _whiteKeys = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  static const _whiteKeyColors = [
    Color(0xFFEF5350),
    Color(0xFFFFCA28),
    Color(0xFF66BB6A),
    Color(0xFF42A5F5),
    Color(0xFFAB47BC),
    Color(0xFFFF7043),
    Color(0xFF26C6DA),
  ];

  @override
  Widget build(BuildContext context) {
    final keys = MediaQuery.of(context).size.width > 900
        ? [..._whiteKeys, ..._whiteKeys]
        : _whiteKeys;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < keys.length; i++)
            Expanded(
              child: Material(
                color: _whiteKeyColors[i % _whiteKeyColors.length],
                child: InkWell(
                  onTap: () =>
                      onNote('${keys[i]}${i < _whiteKeys.length ? 4 : 5}'),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: '${keys[i]}${i < _whiteKeys.length ? 4 : 5}' ==
                                targetNote
                            ? Colors.white
                            : Colors.transparent,
                        width: 4,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${keys[i]}${i < _whiteKeys.length ? 4 : 5}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
