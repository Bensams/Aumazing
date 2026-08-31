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
              color: AppColors.white.withValues(alpha: 0.96),
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.15)),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 24),
              ],
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Header & Title
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Aumazing',
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: AppColors.primaryPurple,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'A Gamified Learning App for Children with\nEarly Childhood Autism Spectrum Disorder',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.mutedForeground,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const _Divider(),
                      
                      // 2. Capstone Team & Characters
                      const _SectionTitle('PROJECT PROPONENTS & DEVELOPERS'),
                      const _PersonCard(
                        name: 'Benedict Paul S. Samson',
                        role: 'Lead Developer & Integration Tester',
                        character: 'BPs',
                        asset: 'bps_none.png',
                      ),
                      const _PersonCard(
                        name: 'Ruel Jr. A. Mendio',
                        role: 'Co-Developer & Functional Tester',
                        character: 'Reiz',
                        asset: 'reiz_none.png',
                      ),
                      const _PersonCard(
                        name: 'Alexandra Mendoza',
                        role: 'Character Inspiration & Contributor',
                        character: 'Lexianne',
                        asset: 'lexianne_none.png',
                      ),
                      const SizedBox(height: 12),
                      const _Divider(),

                      // 3. Expert Validators & Practitioners
                      const _SectionTitle('EXPERT VALIDATORS & PRACTITIONERS'),
                      const _ValidatorCard(
                        name: 'Mrs. Lea Famor',
                        role: 'SPED Teacher & Educational Evaluator',
                        description: 'Evaluated learning module structure and provided domain validation on game appropriateness.',
                      ),
                      const _ValidatorCard(
                        name: 'Mrs. Merrie Grace Domasin Bordaje',
                        role: 'Pre-Assessment Games & Focus Development Contributor',
                        description: 'Contributed the four pre-assessment games and identified focus development areas for children, including communication, social interaction, and play skills.',
                      ),
                      const _ValidatorCard(
                        name: 'Kenneth Ray',
                        role: 'ASD Practitioner & Behavioral Consultant',
                        description: 'Practitioner experienced with ASD children; provided initial user interaction and behavioral feedback.',
                      ),
                      const SizedBox(height: 12),
                      const _Divider(),

                      // 4. Institutional & Capstone Details
                      const _SectionTitle('INSTITUTIONAL & CAPSTONE DETAILS'),
                      const _DetailRow('Institution:', 'Assumption College of Davao'),
                      const _DetailRow('Department:', 'Faculty of Information Technology'),
                      const _DetailRow('Degree / Track:', 'BS in Information Technology (BSIT 2026)'),
                      const _DetailRow('Capstone Adviser:', 'Ms. Christine Marie D. Ordaneza, LPT'),
                      const _DetailRow('Panel Chair:', 'Roselyn M. Biala, MIT'),
                      const SizedBox(height: 24),
                      const _Divider(),

                      // 5. System Architecture & Tech Stack
                      const _SectionTitle('SYSTEM ARCHITECTURE & CORE TECHNOLOGIES'),
                      const _BulletPoint('Mobile & Game Layer: Flutter & Flame 2D Engine'),
                      const _BulletPoint('AI Engine: FastAPI & XGBoost Classifier (Cloud-hosted telemetry assessment)'),
                      const _BulletPoint('Local & Cloud Data: SQLite (Offline-First) & Supabase (PostgreSQL)'),
                      const _BulletPoint('Services: Proximity LBS (Haversine Formula + Google Maps) & PayMongo Gateway'),
                      const SizedBox(height: 24),
                      const _Divider(),

                      // 6. Art, Sound & Sensory Design
                      const _SectionTitle('ART, AUDIO & SENSORY DESIGN'),
                      const _BulletPoint('Mini-games: Copy Me, Match It, Do What I Say, My Turn Your Turn'),
                      const _BulletPoint('Low-sensory UI palettes, adaptive audio suites, voice-over queues, and gentle animations.'),
                      const SizedBox(height: 24),
                      const _Divider(),

                      // 7. Non-Clinical Disclaimer Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.destructiveSoftRed.withValues(alpha: 0.15),
                          borderRadius: AppRadius.button,
                          border: Border.all(color: AppColors.destructiveRed.withValues(alpha: 0.15)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: AppColors.destructiveRed.withValues(alpha: 0.9)),
                                const SizedBox(width: 8),
                                Text(
                                  'DISCLAIMER',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.destructiveRed.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Aumazing is developed strictly as a supplementary educational intervention tool and does not provide medical diagnosis or replace licensed therapy.',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Close credits',
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
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
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.primaryPurple,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Container(
      height: 1,
      color: AppColors.border,
    ),
  );
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
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
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.05),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.1)),
          ),
          child: ClipOval(
            child: Image.asset(
              'packages/shared_ui/assets/costumes/$asset',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.person,
                color: AppColors.primaryPurple.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$role (Character: $character)',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ValidatorCard extends StatelessWidget {
  const _ValidatorCard({
    required this.name,
    required this.role,
    required this.description,
  });
  final String name;
  final String role;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          role,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.primaryPurple.withValues(alpha: 0.8),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
            height: 1.3,
          ),
        ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 10, left: 2),
          child: Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: AppColors.primaryPurple,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
