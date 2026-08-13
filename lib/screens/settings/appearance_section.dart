import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/terminal_palette.dart';
import '../../providers/settings_provider.dart';

/// Monospace families offered in the font picker. These are common
/// cross-platform names; where a family isn't installed, Flutter falls back
/// through xterm's fontFamilyFallback chain (CJK + emoji), so an unavailable
/// pick degrades gracefully rather than crashing. 'JetBrains Mono' resolves
/// only when bundled via pubspec (see assets/fonts).
const _fontOptions = <(String, String)>[
  ('系统默认', defaultFontFamily),
  ('JetBrains Mono', 'JetBrains Mono'),
  ('Menlo', 'Menlo'),
  ('Monaco', 'Monaco'),
  ('Consolas', 'Consolas'),
  ('Liberation Mono', 'Liberation Mono'),
  ('Courier New', 'Courier New'),
];

/// Terminal appearance controls: colour scheme, font family, font size and
/// line height. Renders as a [Column] intended to be embedded in the settings
/// [ListView]; the parent places a [SectionHeader] above it.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            '配色方案',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final palette in TerminalPalette.values)
                _PaletteSwatch(
                  palette: palette,
                  selected: settings.palette == palette,
                  onTap: () => notifier.setPalette(palette),
                ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.font_download),
          title: const Text('字体'),
          trailing: DropdownButton<String>(
            value: _fontOptions
                .any((e) => e.$2 == settings.fontFamily)
            ? settings.fontFamily
            : defaultFontFamily,
            items: [
              for (final (label, value) in _fontOptions)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: (value) {
              if (value != null) notifier.setFontFamily(value);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.format_size),
          title: const Text('字号'),
          subtitle: Slider(
            min: 8,
            max: 28,
            divisions: 20,
            value: settings.fontSize.clamp(8.0, 28.0),
            label: settings.fontSize.toStringAsFixed(0),
            onChanged: notifier.setFontSize,
          ),
          trailing: Text(settings.fontSize.toStringAsFixed(0)),
        ),
        ListTile(
          leading: const Icon(Icons.format_line_spacing),
          title: const Text('行高'),
          subtitle: Slider(
            min: 1.0,
            max: 2.0,
            divisions: 20,
            value: settings.lineHeight.clamp(1.0, 2.0),
            label: settings.lineHeight.toStringAsFixed(2),
            onChanged: notifier.setLineHeight,
          ),
          trailing: Text(settings.lineHeight.toStringAsFixed(2)),
        ),
        // Ligatures require reshaping xterm's per-cell painter into per-run
        // shaping; tracked as future work. Surfaced (disabled) so users know
        // it is a known gap rather than a missing feature.
        SwitchListTile(
          secondary: const Icon(Icons.extension),
          title: const Text('连字 (开发中)'),
          subtitle: const Text('Fira Code 等字体的编程连字，需重写渲染层'),
          value: false,
          onChanged: null,
        ),
      ],
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  final TerminalPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = palette.theme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 84,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? Colors.tealAccent : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: theme.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.brightBlack),
              ),
              alignment: Alignment.center,
              child: Text(
                'Aa',
                style: TextStyle(
                  color: theme.foreground,
                  backgroundColor: theme.background,
                  fontSize: 16,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              palette.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
