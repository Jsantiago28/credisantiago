import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui.dart';

/// Elegir cómo se ve la app en este teléfono: clara u oscura.
class SelectorColores extends StatelessWidget {
  const SelectorColores({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ModoColor>(
      valueListenable: ModoColor.actual,
      builder: (context, modo, _) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.palette_rounded, color: AppColors.green),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Colores de la app', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Cómo quieres ver la app en este teléfono. El claro se lee mejor al sol.',
                style: TextStyle(color: AppColors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            SegmentedButton<ModoColor>(
              segments: const [
                ButtonSegment(
                    value: ModoColor.claro,
                    icon: Icon(Icons.light_mode_rounded),
                    label: Text('Claro')),
                ButtonSegment(
                    value: ModoColor.oscuro,
                    icon: Icon(Icons.dark_mode_rounded),
                    label: Text('Oscuro')),
              ],
              selected: {modo},
              showSelectedIcon: false,
              onSelectionChanged: (elegidos) => ModoColor.elegir(elegidos.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.greenDark,
                selectedForegroundColor: AppColors.green,
                foregroundColor: AppColors.grey,
                side: BorderSide(color: AppColors.border),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
