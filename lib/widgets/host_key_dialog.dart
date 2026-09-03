import 'package:flutter/material.dart';

/// Dialog shown on first contact with an unknown SSH host (TOFU). Asks the
/// user whether to trust and remember the presented host key.
///
/// [fingerprint] is the canonical form from
/// `canonicalHostKeyFingerprint` — `SHA256:<base64>` or `MD5:aa:bb:...`,
/// exactly what `ssh-keygen -l` prints, so what the user verifies
/// out-of-band is what gets remembered.
///
/// Returns true if the user accepts, false/null otherwise.
Future<bool?> showHostKeyDialog({
  required BuildContext context,
  required String host,
  required int port,
  required String keyType,
  required String fingerprint,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Unknown Host'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('First connection to:'),
          const SizedBox(height: 4),
          Text(
            '$host:$port',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text('Host key type:'),
          const SizedBox(height: 4),
          Text(keyType, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 12),
          Text('Fingerprint:'),
          const SizedBox(height: 4),
          SelectableText(
            fingerprint,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            'Trust this host and remember its key? An attacker could replace '
            'it later — only accept if you verify the fingerprint out-of-band.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(ctx).colorScheme.error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Abort'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Trust'),
        ),
      ],
    ),
  );
}
