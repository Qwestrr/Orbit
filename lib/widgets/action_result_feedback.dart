import 'package:flutter/material.dart';

/// Awaits a bool result from a pushed route/dialog and shows a snackbar
/// only when the result is true.
Future<void> showSuccessForResult({
  required BuildContext context,
  required Future<bool?> result,
  required String message,
}) async {
  final success = await result;
  if (success == true && context.mounted) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}