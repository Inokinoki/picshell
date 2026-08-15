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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final warning = ref.read(launchSecurityWarningProvider);
      if (warning == null) return;
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
