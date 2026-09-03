import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/vault_provider.dart';

/// Full-screen biometric gate shown while [appLockProvider] is locked. Tapping
/// unlock triggers the system biometric prompt; on success the vault releases
/// the master key and the app continues. A failure (cancel / no match) lets the
/// user retry. There is deliberately no "forgot" path — under the device-key
/// model the user has no password to forget.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    bool ok;
    try {
      ok = await ref.read(appLockProvider.notifier).unlock();
    } catch (_) {
      // local_auth can throw (LockedOut, plugin errors) — treat like a
      // failed attempt so the user can retry instead of a stranded spinner.
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
    // On success the provider flips to unlocked and the app rebuilds without
    // this screen, so no setState needed.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Picshell is locked',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Saved passwords and private keys are encrypted with a '
                  'device-bound key.\n'
                  'Unlock with Face ID / fingerprint.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Unlock failed. Please try again.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : _unlock,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
