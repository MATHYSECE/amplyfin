import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bouton « Voir le détail » qui déplie le message technique d'une erreur
/// (pour comprendre ce qui s'est passé, sur iPhone par exemple).
class ErrorDetails extends StatefulWidget {
  const ErrorDetails(this.detail, {super.key});

  final String detail;

  @override
  State<ErrorDetails> createState() => _ErrorDetailsState();
}

class _ErrorDetailsState extends State<ErrorDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => setState(() => _open = !_open),
          child: Text(_open ? 'Masquer le détail' : 'Voir le détail'),
        ),
        if (_open)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: SelectableText(
                widget.detail,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: AppColors.grey),
              ),
            ),
          ),
      ],
    );
  }
}
