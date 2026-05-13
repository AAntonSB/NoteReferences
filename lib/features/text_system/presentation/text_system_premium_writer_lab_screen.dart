import 'package:flutter/material.dart';

import '../premium/premium_writer_screen.dart';

class TextSystemPremiumWriterLabScreen extends StatelessWidget {
  const TextSystemPremiumWriterLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PremiumWriterScreen(
      screenTitle: 'Premium writer lab',
      showInspectorByDefault: true,
    );
  }
}
