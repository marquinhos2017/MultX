import 'package:flutter/material.dart';

class PanControl extends StatelessWidget {
  final int index;
  final double pan;
  final Function(int, double) setPlayerPan;

  const PanControl({
    Key? key,
    required this.index,
    required this.pan,
    required this.setPlayerPan,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> options = [
      {"label": "1", "value": -1.0},
      {"label": "C", "value": 0.0},
      {"label": "2", "value": 1.0},
    ];

    String currentLabel = options.firstWhere(
      (o) => o["value"] == pan,
      orElse: () => {"label": "C"},
    )["label"];

    return SizedBox(
      width: 80,
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (ctx) {
              return Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.deepPurpleAccent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: options.map((option) {
                        return InkWell(
                          onTap: () {
                            setPlayerPan(index, option["value"]);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 16,
                            ),
                            child: Text(
                              option["label"],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13, // 🔥 fonte menor no popup
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );
            },
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.deepPurpleAccent, width: 1.2),
          ),
          child: Center(
            child: Text(
              currentLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12, // 🔥 fonte menor no campo
              ),
            ),
          ),
        ),
      ),
    );
  }
}
