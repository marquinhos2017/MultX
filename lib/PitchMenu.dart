import 'package:flutter/material.dart';

class FloatingPitchControl extends StatefulWidget {
  final int globalPitch;
  final ValueChanged<int> onPitchChange;

  const FloatingPitchControl({
    super.key,
    required this.globalPitch,
    required this.onPitchChange,
  });

  @override
  State<FloatingPitchControl> createState() => _FloatingPitchControlState();
}

class _FloatingPitchControlState extends State<FloatingPitchControl> {
  OverlayEntry? _overlayEntry;

  void _showOverlay(BuildContext context) {
    if (_overlayEntry != null) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: offset.dy + renderBox.size.height + 8,
        left: offset.dx,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _changePitch(-100),
                  icon: const Icon(Icons.remove, color: Colors.redAccent),
                  tooltip: "-1 semitom",
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    (widget.globalPitch / 100).round().toString(),
                    style: const TextStyle(
                      color: Colors.deepPurpleAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _changePitch(100),
                  icon: const Icon(Icons.add, color: Colors.greenAccent),
                  tooltip: "+1 semitom",
                ),
                IconButton(
                  onPressed: _resetPitch,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: "Resetar",
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _changePitch(int delta) {
    int newPitch = (widget.globalPitch + delta).clamp(-1200, 1200);
    widget.onPitchChange(newPitch);
  }

  void _resetPitch() {
    widget.onPitchChange(0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_overlayEntry == null) {
          _showOverlay(context);
        } else {
          _hideOverlay();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note, color: Colors.deepPurpleAccent),
            const SizedBox(width: 6),
            Text(
              (widget.globalPitch / 100).round().toString(),
              style: const TextStyle(
                color: Colors.deepPurpleAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _overlayEntry == null
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_up,
              color: Colors.deepPurpleAccent,
            ),
          ],
        ),
      ),
    );
  }
}
