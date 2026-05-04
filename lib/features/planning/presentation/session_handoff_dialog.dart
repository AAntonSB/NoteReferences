import 'package:flutter/material.dart';

class EndSessionDialog extends StatefulWidget {
  final String projectTitle;

  const EndSessionDialog({super.key, required this.projectTitle});

  @override
  State<EndSessionDialog> createState() => _EndSessionDialogState();
}

class _EndSessionDialogState extends State<EndSessionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('End session'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What should future you remember when returning to “${widget.projectTitle}”?'),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 5,
              maxLines: 9,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'One item per line\nContinue from p. 142\nCheck why assumption 2 is needed\nTurn the highlight into a note',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            final items = _controller.text
                .split(RegExp(r'\r?\n'))
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty)
                .toList(growable: false);
            if (items.isEmpty) return;
            Navigator.of(context).pop(items);
          },
          icon: const Icon(Icons.save_rounded),
          label: const Text('Save for next session'),
        ),
      ],
    );
  }
}
