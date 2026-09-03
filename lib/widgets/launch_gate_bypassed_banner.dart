import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vault_provider.dart';

/// Shows a persistent [MaterialBanner] warning the user when the launch
/// biometric gate was bypassed (see `launchSecurityWarningProvider` and
/// `performLaunchUnlock`). Must be mounted inside a [MaterialApp] so a
/// [ScaffoldMessenger] is available; the app shell wraps the router with it.
class LaunchGateBypassedBanner extends ConsumerStatefulWidget {
  final Widget? child;

  const LaunchGateBypassedBanner({super.key, this.child});

  @override
  ConsumerState<LaunchGateBypassedBanner> createState() =>
      _LaunchGateBypassedBannerState();
}

class _LaunchGateBypassedBannerState
    extends ConsumerState<LaunchGateBypassedBanner> {
  /// User-facing warning text for the launch-security status. Lives here (not
  /// in `main()`) so startup wiring stays free of presentation strings.
  static String _warningText(LaunchGateStatus status) {
    if (status.gateBypassed && status.reEncryptionFailed) {
      return 'Biometric unlock is required, but biometrics are currently '
          'unavailable on this device and the passcode fallback failed. '
          'Your credentials were unlocked WITHOUT verification so they stay '
          'readable. Re-enrol biometrics (system settings) to restore the '
          'gate.\nAdditionally, some saved credentials could not be '
          're-encrypted and are still stored unencrypted.';
    }
    if (status.gateBypassed) {
      return 'Biometric unlock is required, but biometrics are currently '
          'unavailable on this device and the passcode fallback failed. '
          'Your credentials were unlocked WITHOUT verification so they stay '
          'readable. Re-enrol biometrics (system settings) to restore the '
          'gate.';
    }
    return 'Biometric encryption is enabled, but finishing the encryption of '
        'your saved credentials failed (an earlier attempt was interrupted). '
        'Some passwords or private keys may still be stored unencrypted. '
        'Reopen Settings and toggle biometric encryption to retry.';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final status = ref.read(launchSecurityWarningProvider);
      if (status == null || status.isEmpty) return;
      final warning = _warningText(status);
      final messenger = ScaffoldMessenger.of(context);
      if (messenger.mounted) {
        messenger.showMaterialBanner(
          MaterialBanner(
            content: Text(warning),
            backgroundColor: Colors.amber.shade100,
            leading: const Icon(Icons.warning_amber_rounded,
                color: Colors.deepOrange),
            actions: [
              TextButton(
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}
