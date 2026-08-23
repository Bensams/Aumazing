import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Shows the people, project context, and creative/technical credits for Aumazing.
Future<void> showCreditsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const CreditsDialog(),
  );
}

class CreditsDialog extends StatelessWidget {
  const CreditsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: AppRadius.card,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.92),
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.white.withValues(alpha: 0.7)),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 24),
              ],
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Credits', style: AppTextStyles.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Aumazing - Gamified Early Intervention for Children with ASD',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _sectionTitle('Capstone Team & Characters'),
                      const SizedBox(height: 10),
                      const _Person(
                        name: 'Benedict Paul S. Samson',
                        role: 'Lead Developer & Project Lead',
                        character: 'BPs',
                        asset: 'bps_none.png',
                      ),
                      const _Person(
                        name: 'Ruel Jr. A. Mendio',
                        role: 'Capstone Partner & Co-Developer',
                        character: 'Reiz',
                        asset: 'reiz_none.png',
                      ),
                      const _Person(
                        name: 'Alexandra Mendoza',
                        role: 'Character Inspiration & Contributor',
                        character: 'Lexianne',
                        asset: 'lexianne_none.png',
                      ),
                      const SizedBox(height: 18),
                      _sectionTitle('Institutional & Capstone Details'),
                      const SizedBox(height: 8),
                      const _Body(
                        'Faculty of Information Technology, Assumption College of Davao (BSIT Capstone 2026).',
                      ),
                      const _Body('Adviser: Roselyn M. Biala, MIT'),
                      const _Body(
                        'Subject Instructor: Ms. Christine Marie D. Ordaneza, LPT',
                      ),
                      const SizedBox(height: 18),
                      _sectionTitle('Art & Visual Media'),
                      const _Body(
                        'Character designs, cosmic video backgrounds, interactive cursor packs, and animations.',
                      ),
                      const SizedBox(height: 14),
                      _sectionTitle('Audio & Music'),
                      const _Body(
                        'Adaptive ambient soundscapes, curated BGM suites (Filipino Calm, Gentle Playful, Focus Minimal, Soft Relaxing, Lyria 3 Pro), sound effects, and voice overs.',
                      ),
                      const SizedBox(height: 14),
                      _sectionTitle('Open Source & Technology'),
                      const _Body(
                        'Built with Flutter, Dart, Supabase, Riverpod, and the wider open-source ecosystem.',
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'Close credits',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: AppTextStyles.titleMedium.copyWith(
      color: AppColors.primaryPurple,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _Person extends StatelessWidget {
  const _Person({
    required this.name,
    required this.role,
    required this.character,
    required this.asset,
  });
  final String name;
  final String role;
  final String character;
  final String asset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'packages/shared_ui/assets/costumes/$asset',
          width: 58,
          height: 58,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$role - Character: $character',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: AppTextStyles.bodySmall),
  );
}
