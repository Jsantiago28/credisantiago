import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../logic/dominio.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

export '../logic/dominio.dart';

class LinkGeneradoScreen extends StatelessWidget {
  final String slug;
  const LinkGeneradoScreen({super.key, required this.slug});

  String get link => '$kDominioBase/s/$slug';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: AppColors.green, size: 64),
              const SizedBox(height: 16),
              const Text(
                '¡Tu link está listo!',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Mándaselo a tus clientes por WhatsApp para que soliciten su préstamo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.grey),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        link,
                        style: TextStyle(
                            color: AppColors.green, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, color: AppColors.grey),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: link));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copiado')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Share.share(
                    'Solicita tu préstamo aquí sin venir a mi casa, llena esto y te digo si te apruebo: $link',
                  );
                },
                icon: const Icon(Icons.share),
                label: const Text('Compartir por WhatsApp'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const HomeShell()),
                  );
                },
                child: const Text('Ir a mi dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
