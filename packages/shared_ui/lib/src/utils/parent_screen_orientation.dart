import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'device_form_factor.dart';

/// The orientations a child-facing screen allows: landscape, both ways.
const List<DeviceOrientation> kChildOrientations = [
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

/// The orientations a parent-facing screen allows on a device whose smallest
/// screen width is [smallestWidthDp].
///
/// Phones get portrait; tablets stay landscape, matching the startup
/// orientation Android picked from `res/values-sw600dp/orientation.xml`. A
/// tablet must never be handed portrait here: Android would letterbox the
/// window into a phone-shaped strip and the app would never get back out.
List<DeviceOrientation> parentOrientationsFor(double smallestWidthDp) =>
    smallestWidthDp < kTabletSmallestWidthDp
        ? const [DeviceOrientation.portraitUp]
        : kChildOrientations;

/// Locks landscape on every device. For the screens the *child* uses — child
/// mode, the games, and the assessment activities — which are designed wide.
/// Parent-facing screens use [lockParentAdaptive] instead.
void lockParentLandscape() {
  SystemChrome.setPreferredOrientations(kChildOrientations);
}

/// Call when leaving a child-facing screen — restores the parent policy.
void unlockParentOrientation() {
  lockParentAdaptive();
}

/// Orientation policy for parent-facing screens: phones stay portrait (the
/// parent UI lays out as a single column on a narrow screen, and a parent
/// holds their phone upright), while tablets stay landscape to match the
/// child experience.
void lockParentAdaptive() {
  SystemChrome.setPreferredOrientations(
    parentOrientationsFor(deviceSmallestWidthDp),
  );
}

/// True when the parent UI is running in its portrait phone layout. Screens
/// use this to pick a stacked layout over the wide side-by-side one.
///
/// Prefer `MediaQuery`-based checks inside `build`; this is for the cases
/// where the decision has to be made outside the widget tree.
bool get isParentPortraitDevice => isPhoneFormFactor;

/// Wraps a parent-facing screen that has no [State] of its own, locking the
/// adaptive parent orientation while it is mounted. Stateful screens call
/// [lockParentAdaptive] from `initState` instead.
///
/// Needed because these screens can be reached from a landscape child-facing
/// screen (e.g. the assessment results shown after the child finishes), and
/// the lock has to flip back to portrait on entry.
class ParentAdaptiveOrientation extends StatefulWidget {
  const ParentAdaptiveOrientation({super.key, required this.child});

  final Widget child;

  @override
  State<ParentAdaptiveOrientation> createState() =>
      _ParentAdaptiveOrientationState();
}

class _ParentAdaptiveOrientationState extends State<ParentAdaptiveOrientation> {
  @override
  void initState() {
    super.initState();
    lockParentAdaptive();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
