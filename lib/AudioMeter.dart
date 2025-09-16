import 'dart:async';

import 'package:flutter/material.dart';

class AudioMeter extends StatefulWidget {
  final int index;
  final double height;

  const AudioMeter({Key? key, required this.index, this.height = 40})
    : super(key: key);

  @override
  _AudioMeterState createState() => _AudioMeterState();
}

class _AudioMeterState extends State<AudioMeter> with TickerProviderStateMixin {
  late AnimationController _animationController;
  double _currentLevel = 0.0;
  Timer? _levelTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 100),
    );
    _startLevelUpdates();
  }

  void _startLevelUpdates() async {
    _levelTimer = Timer.periodic(Duration(milliseconds: 50), (timer) async {
      try {} catch (e) {
        print('Error getting audio level: $e');
      }
    });
  }

  @override
  void dispose() {
    _levelTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      width: 8,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Container(
                  height: _currentLevel * widget.height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _currentLevel > 0.9
                            ? Colors.red
                            : _currentLevel > 0.7
                            ? Colors.yellow
                            : Colors.green,
                        Colors.greenAccent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
