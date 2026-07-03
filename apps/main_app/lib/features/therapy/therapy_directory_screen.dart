import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/therapy_center.dart';
import '../../providers/child_provider.dart';
import '../../services/therapy_center_service.dart';

/// Therapy Center Directory + Interactive Locator (Use Cases 11, 15, 16).
///
/// Shows registered Davao City therapy/SPED centers. "Find near me"
/// requests a just-in-time GPS fix, ranks the list with the Haversine
/// formula, and shows distances; the position lives only in this screen's
/// state and is discarded with it (privacy FR — never persisted).
/// "Directions" hands off to the device's native maps app.
class TherapyDirectoryScreen extends StatefulWidget {
  const TherapyDirectoryScreen({super.key});

  @override
  State<TherapyDirectoryScreen> createState() => _TherapyDirectoryScreenState();
}

class _TherapyDirectoryScreenState extends State<TherapyDirectoryScreen> {
  List<TherapyCenter> _centers = const [];
  List<RankedTherapyCenter>? _ranked; // null until a GPS fix succeeds
  bool _loading = true;
  bool _locating = false;
  String? _locationMessage;

  @override
  void initState() {
    super.initState();
    _loadCenters();
  }

  Future<void> _loadCenters() async {
    final centers = await TherapyCenterService.instance.getCenters();
    if (!mounted) return;
    setState(() {
      _centers = centers;
      _loading = false;
    });
  }

  /// Just-in-time GPS fix: permission is requested only when the parent
  /// taps "Find near me", and the position never leaves this method's
  /// scope except as ranked distances.
  Future<void> _findNearMe() async {
    setState(() {
      _locating = true;
      _locationMessage = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() =>
            _locationMessage = 'Turn on Location to rank centers by distance.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _locationMessage =
            'Location permission is needed to rank centers by distance.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() {
        _ranked = TherapyCenterService.rankByDistance(
          _centers,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      });
    } catch (e) {
      if (mounted) {
        setState(
            () => _locationMessage = 'Could not get your location right now.');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Native map hand-off: geo: URI (Android intent) with a Google Maps
  /// web fallback for devices without a maps app.
  Future<void> _openDirections(TherapyCenter center) async {
    final label = Uri.encodeComponent(center.name);
    final geoUri = Uri.parse(
        'geo:${center.latitude},${center.longitude}?q=${center.latitude},'
        '${center.longitude}($label)');
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
      return;
    }
    final webUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination='
        '${center.latitude},${center.longitude}');
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<ChildProvider>().activePalette;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: palette.parentBackground),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(palette),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _centers.isEmpty
                        ? _buildEmpty()
                        : _buildList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(GamePalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          Material(
            color: AppColors.white.withValues(alpha: 0.85),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.arrow_back_rounded, color: palette.primary),
              tooltip: 'Back',
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Therapy Directory',
                  style: AppTextStyles.headlineSmall.copyWith(
                    color: palette.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'SPED and therapy centers in Davao City',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.mutedForeground),
                ),
              ],
            ),
          ),
          AppPrimaryButton(
            label: _ranked == null ? 'Find near me' : 'Update location',
            icon: Icons.my_location_rounded,
            isLoading: _locating,
            onPressed: _locating ? null : _findNearMe,
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        'No therapy centers available yet.\nConnect to the internet once to '
        'load the directory.',
        textAlign: TextAlign.center,
        style:
            AppTextStyles.bodyMedium.copyWith(color: AppColors.mutedForeground),
      ),
    );
  }

  Widget _buildList() {
    final ranked = _ranked;
    final itemCount = ranked?.length ?? _centers.length;

    return Column(
      children: [
        if (_locationMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              _locationMessage!,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.statusWarningDark),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: itemCount,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) {
              final center = ranked?[i].center ?? _centers[i];
              final distanceKm = ranked?[i].distanceKm;
              return _CenterCard(
                center: center,
                distanceKm: distanceKm,
                onDirections: () => _openDirections(center),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({
    required this.center,
    required this.onDirections,
    this.distanceKm,
  });

  final TherapyCenter center;
  final double? distanceKm;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.lavenderLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_hospital_rounded,
                color: AppColors.primaryPurple),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        center.name,
                        style: AppTextStyles.titleMedium
                            .copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    if (distanceKm != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.mint.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${distanceKm!.toStringAsFixed(1)} km',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  center.address,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.mutedForeground),
                ),
                if (center.description != null &&
                    center.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    center.description!,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.mutedForeground),
                  ),
                ],
                if (center.services.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final service in center.services)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppColors.lavenderLight.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            service,
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onDirections,
                    icon: const Icon(Icons.directions_rounded, size: 18),
                    label: const Text('Directions'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
