import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/therapy_center.dart';
import 'therapy_map_support.dart';

/// Embedded therapy-center map (AUM-164).
///
/// All provider-specific code lives behind this widget: OpenStreetMap
/// raster tiles through flutter_map — chosen because it needs no API key,
/// so no mapping secret can end up in source control. The required OSM
/// attribution is rendered on the map and taps through to the copyright
/// page.
///
/// The map never touches location APIs — the parent's position arrives
/// (optionally) from the directory screen's existing "Find near me" flow
/// and is only ever held in widget state. Tile failures degrade to a
/// non-blocking banner; markers and the directory list keep working.
/// Tiles are fetched from the network and are NOT cached for offline use.
class TherapyMapView extends StatefulWidget {
  const TherapyMapView({
    super.key,
    required this.centers,
    this.selectedCenterId,
    this.onMarkerTap,
    this.userLatitude,
    this.userLongitude,
    this.tileProvider,
  });

  /// All centers; invalid coordinates are filtered out here, never drawn.
  final List<TherapyCenter> centers;

  /// Stable center ID whose marker is highlighted and focused.
  final String? selectedCenterId;

  final ValueChanged<String>? onMarkerTap;

  /// Parent's position from a granted "Find near me" fix — in memory only,
  /// never persisted (privacy FR).
  final double? userLatitude;
  final double? userLongitude;

  /// Test seam: replaces the network tile provider so widget tests never
  /// fetch live tiles.
  final TileProvider? tileProvider;

  /// Test seam for screens that embed this widget indirectly: when set,
  /// any [TherapyMapView] without an explicit [tileProvider] uses it.
  @visibleForTesting
  static TileProvider Function()? debugTileProviderFactory;

  @override
  State<TherapyMapView> createState() => TherapyMapViewState();
}

class TherapyMapViewState extends State<TherapyMapView> {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _tilesUnavailable = false;

  @visibleForTesting
  MapController get debugMapController => _mapController;

  @visibleForTesting
  bool get debugTilesUnavailable => _tilesUnavailable;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TherapyMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.selectedCenterId;
    if (id != null && id != oldWidget.selectedCenterId) {
      _focusCenter(id);
    }
  }

  /// Centers the camera on [id]'s marker. flutter_map's `move` is an
  /// instant jump (no animation), which also satisfies reduced-motion
  /// preferences by construction.
  void _focusCenter(String id) {
    if (!_mapReady) return;
    TherapyCenter? target;
    for (final c in widget.centers) {
      if (c.id == id && TherapyMapSupport.hasValidCoordinates(c)) {
        target = c;
        break;
      }
    }
    if (target == null) return;
    final zoom = math.max(
      _mapController.camera.zoom,
      TherapyMapSupport.singleCenterZoom,
    );
    _mapController.move(LatLng(target.latitude, target.longitude), zoom);
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final camera = _mapController.camera;
    _mapController.move(
      camera.center,
      (camera.zoom + delta).clamp(_minZoom, _maxZoom).toDouble(),
    );
  }

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    debugPrint('[TherapyMap] tile failed to load: $error');
    if (_tilesUnavailable || !mounted) return;
    setState(() => _tilesUnavailable = true);
  }

  /// Test seam: what [_onTileError] reports when a tile fails, without
  /// needing a real failed fetch (widget tests never touch the network).
  @visibleForTesting
  void debugSimulateTileFailure() {
    if (_tilesUnavailable || !mounted) return;
    setState(() => _tilesUnavailable = true);
  }

  static const double _minZoom = 3;
  static const double _maxZoom = 18;

  @override
  Widget build(BuildContext context) {
    final mappable = TherapyMapSupport.mappableCenters(widget.centers);
    if (mappable.isEmpty) {
      // No coordinates worth drawing — a clear placeholder instead of an
      // empty world map.
      return _MapPlaceholder(
        message:
            'Center locations aren\'t available on the map yet.\n'
            'The list below still has every center.',
      );
    }

    final bounds = TherapyMapSupport.boundsFor(widget.centers)!;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    var flags =
        InteractiveFlag.drag |
        InteractiveFlag.pinchZoom |
        InteractiveFlag.doubleTapZoom |
        InteractiveFlag.scrollWheelZoom;
    if (!reduceMotion) flags |= InteractiveFlag.flingAnimation;

    final options =
        bounds.isSinglePoint
            ? MapOptions(
              initialCenter: LatLng(bounds.southLat, bounds.westLng),
              initialZoom: TherapyMapSupport.singleCenterZoom,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              backgroundColor: AppColors.lavenderLight,
              onMapReady: () => _mapReady = true,
              interactionOptions: InteractionOptions(flags: flags),
            )
            : MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds(
                  LatLng(bounds.southLat, bounds.westLng),
                  LatLng(bounds.northLat, bounds.eastLng),
                ),
                padding: const EdgeInsets.all(36),
              ),
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              backgroundColor: AppColors.lavenderLight,
              onMapReady: () => _mapReady = true,
              interactionOptions: InteractionOptions(flags: flags),
            );

    return Semantics(
      label: 'Map of therapy centers',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: options,
              children: [
                // Public OpenStreetMap raster tiles over HTTPS with zoom
                // bounded to [_minZoom, _maxZoom]; no API key, and no
                // prefetching or bulk/offline tile downloading. Production
                // deployments must comply with the selected tile provider's
                // usage policy (for OSM: visible attribution and an
                // identifying user agent — userAgentPackageName is the
                // app's Android application ID).
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.aumazing',
                  tileProvider:
                      widget.tileProvider ??
                      TherapyMapView.debugTileProviderFactory?.call() ??
                      NetworkTileProvider(),
                  errorTileCallback: _onTileError,
                ),
                MarkerLayer(markers: _buildMarkers(mappable)),
              ],
            ),
            const Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Align(
                alignment: Alignment.bottomRight,
                child: _MapAttribution(),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Column(
                children: [
                  _MapControlButton(
                    icon: Icons.add_rounded,
                    tooltip: 'Zoom in',
                    onTap: () => _zoomBy(1),
                  ),
                  const SizedBox(height: 6),
                  _MapControlButton(
                    icon: Icons.remove_rounded,
                    tooltip: 'Zoom out',
                    onTap: () => _zoomBy(-1),
                  ),
                ],
              ),
            ),
            if (_tilesUnavailable)
              Positioned(
                top: 8,
                left: 8,
                right: 56,
                child: _TilesUnavailableBanner(),
              ),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildMarkers(List<TherapyCenter> mappable) {
    return [
      for (final center in mappable)
        Marker(
          key: ValueKey('therapy-marker-${center.id}'),
          point: LatLng(center.latitude, center.longitude),
          width: 48,
          height: 48,
          // Pin tip sits on the coordinate.
          alignment: Alignment.topCenter,
          child: Semantics(
            label: '${center.name} map marker',
            button: true,
            selected: center.id == widget.selectedCenterId,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap:
                  widget.onMarkerTap == null
                      ? null
                      : () => widget.onMarkerTap!(center.id),
              child: Icon(
                Icons.location_pin,
                size: center.id == widget.selectedCenterId ? 44 : 34,
                color:
                    center.id == widget.selectedCenterId
                        ? AppColors.primaryPurple
                        : AppColors.primaryPurple.withValues(alpha: 0.75),
                shadows: const [Shadow(color: Colors.black26, blurRadius: 4)],
              ),
            ),
          ),
        ),
      if (widget.userLatitude != null && widget.userLongitude != null)
        Marker(
          key: const ValueKey('therapy-user-marker'),
          point: LatLng(widget.userLatitude!, widget.userLongitude!),
          width: 22,
          height: 22,
          child: Semantics(
            label: 'Your location',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.white, width: 3),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4),
                ],
              ),
            ),
          ),
        ),
    ];
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: AppColors.primaryPurple),
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// OpenStreetMap attribution, required by the OSM tile usage policy.
///
/// flutter_map's own `SimpleAttributionWidget` lays its label out in an
/// unconstrained `Row`, which overflows on a phone-width map; this keeps
/// the same credit and copyright link inside the map's width.
class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: GestureDetector(
        onTap:
            () => launchUrl(
              Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication,
            ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '© OpenStreetMap contributors',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textPrimary,
              fontSize: 10,
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-blocking notice when tiles can't load (offline, tile server down):
/// markers and the list keep working; only the imagery is missing.
class _TilesUnavailableBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Map imagery unavailable right now — the center list still works.',
        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lavenderLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.map_outlined,
            size: 32,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
