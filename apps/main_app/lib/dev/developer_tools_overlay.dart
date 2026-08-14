import 'package:flutter/material.dart';

import 'developer_automation_bar.dart';
import 'developer_autoplay_controller.dart';
import 'developer_tools_config.dart';
import 'developer_tools_panel.dart';

/// Root navigator key, installed on [MaterialApp] only while the developer
/// toolbox is available.
///
/// The toolbox lives in `MaterialApp.builder`, which sits *above* the
/// navigator — so it has no `Navigator.of(context)` of its own. This key is
/// how it opens the sheet and installs the hand-off route, from wherever the
/// app currently is (a game, a dialog, an assessment progress screen).
final GlobalKey<NavigatorState> developerToolsNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'developerTools');

/// A small, draggable, unmistakably-developer button floated above every
/// route — and nothing at all when the toolbox is unavailable.
class DeveloperToolsOverlay extends StatefulWidget {
  const DeveloperToolsOverlay({super.key, required this.child});

  final Widget child;

  /// Drop-in for `MaterialApp.builder`.
  ///
  /// Returns [child] untouched when the toolbox is unavailable, so a
  /// production build has no extra widget — not a hidden one — in the tree.
  static Widget wrap(BuildContext context, Widget? child) {
    final content = child ?? const SizedBox.shrink();
    if (!DeveloperToolsConfig.isAvailable) return content;
    return DeveloperToolsOverlay(child: content);
  }

  /// The navigator key to hand [MaterialApp], or null in a normal build so
  /// the app's navigator behaviour is exactly as it was.
  static GlobalKey<NavigatorState>? get navigatorKey =>
      DeveloperToolsConfig.isAvailable ? developerToolsNavigatorKey : null;

  @override
  State<DeveloperToolsOverlay> createState() => _DeveloperToolsOverlayState();
}

class _DeveloperToolsOverlayState extends State<DeveloperToolsOverlay> {
  /// Where the parent has dragged the button, in logical pixels (top-left).
  /// Null until it is dragged: until then the button parks in its default
  /// corner, which follows rotations and window resizes for free.
  Offset? _dragged;

  static const double _buttonWidth = 68;
  static const double _buttonHeight = 40;
  static const double _margin = 12;

  /// The button lives in an [Overlay] of its own rather than straight in the
  /// [Stack]: it floats *above* the app's navigator, so it cannot borrow the
  /// navigator's overlay — and without one, its [Tooltip] has nowhere to
  /// render.
  /// Owned by the [Overlay] they are handed to, which disposes them with
  /// itself. The automation bar is a separate entry from the button: it is
  /// pinned to the top and must not move when the button is dragged.
  late final OverlayEntry _entry = OverlayEntry(builder: _buildButton);
  late final OverlayEntry _barEntry = OverlayEntry(builder: _buildAutomationBar);

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      // Tight constraints for the app, exactly as it gets without the
      // overlay — only the developer chrome is floated on top.
      fit: StackFit.expand,
      children: [
        widget.child,
        Overlay(initialEntries: [_barEntry, _entry]),
      ],
    );
  }

  Widget _buildAutomationBar(BuildContext context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Align(
          alignment: Alignment.topCenter,
          child: DeveloperAutomationBar(onSkipRemaining: _confirmSkipRemaining),
        ),
      );

  /// Skipping the rest of a flow writes a session for every remaining game,
  /// so it asks first.
  Future<void> _confirmSkipRemaining() async {
    final navigatorContext = developerToolsNavigatorKey.currentContext;
    if (navigatorContext == null) return;

    final confirmed = await showDialog<bool>(
      context: navigatorContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Skip remaining games?'),
        content: const Text(
          'The current game and every game left in this flow will be played '
          'to completion by automation. One real session is recorded per '
          'game, and the flow finishes the way it normally would — an '
          'assessment still ends at the hand-off to the parent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DeveloperAutoPlayController.instance.skipRemainingGames();
  }

  Widget _buildButton(BuildContext context) {
    final media = MediaQuery.of(context);

    // Keep the button inside the safe area in both orientations.
    final minX = media.padding.left + _margin;
    final minY = media.padding.top + _margin;
    final maxX =
        media.size.width - media.padding.right - _margin - _buttonWidth;
    final maxY =
        media.size.height - media.padding.bottom - _margin - _buttonHeight;
    // A very small window can invert the range; clamp() would throw.
    final hiX = maxX < minX ? minX : maxX;
    final hiY = maxY < minY ? minY : maxY;

    // Default: bottom-left, the corner least likely to sit on a game's
    // controls or a dialog's primary button. Re-clamped on every build, so a
    // rotation can never strand it off-screen.
    final position = Offset(
      (_dragged?.dx ?? minX).clamp(minX, hiX),
      (_dragged?.dy ?? maxY).clamp(minY, hiY),
    );

    // Must be the entry's outermost widget: the overlay lays its entries out
    // in a Stack, and Positioned has to be a direct child of one.
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: _DevButton(
        width: _buttonWidth,
        height: _buttonHeight,
        onDrag: (delta) {
          _dragged = Offset(
            (position.dx + delta.dx).clamp(minX, hiX),
            (position.dy + delta.dy).clamp(minY, hiY),
          );
          _entry.markNeedsBuild();
        },
        onTap: _openToolbox,
      ),
    );
  }

  void _openToolbox() {
    final navigatorContext = developerToolsNavigatorKey.currentContext;
    if (navigatorContext == null) return;
    DeveloperToolsPanel.show(navigatorContext);
  }
}

class _DevButton extends StatelessWidget {
  const _DevButton({
    required this.width,
    required this.height,
    required this.onDrag,
    required this.onTap,
  });

  final double width;
  final double height;
  final void Function(Offset delta) onDrag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Developer tools',
      button: true,
      // Its own node, so the InkWell's button semantics underneath cannot
      // swallow the label that says what this button is.
      container: true,
      child: Tooltip(
        message: 'Developer Tools (debug build only)',
        child: Material(
          color: const Color(0xCC1B1B1F),
          elevation: 6,
          borderRadius: BorderRadius.circular(height / 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: onTap,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (details) => onDrag(details.delta),
              child: SizedBox(
                width: width,
                height: height,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.developer_mode_rounded,
                        size: 18, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'DEV',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
