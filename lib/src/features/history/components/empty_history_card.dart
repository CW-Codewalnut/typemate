import 'package:flutter/material.dart';

class EmptyHistoryCard extends StatelessWidget {
  const EmptyHistoryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.mic_none, size: 40),
            SizedBox(height: 12),
            Text('No speech history yet.'),
            SizedBox(height: 4),
            Text(
              'Hold the shortcut, speak, and your generated text will appear here.',
            ),
          ],
        ),
      ),
    );
  }
}
