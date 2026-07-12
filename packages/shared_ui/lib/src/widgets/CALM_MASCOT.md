# CalmMascot — ASD-safe character widget

A drop-in animated mascot (BPs / Reiz) that **cannot overstimulate** — the
calm-motion limits are baked in, so any use stays inside the safe envelope.

## Safe-motion envelope (enforced by the widget)

| Parameter | Value | Note |
|---|---|---|
| Breathing idle | scale 1.0 ↔ ≤1.06 over ~2.6 s, ease-in-out | one still image, no jitter |
| Gesture rate | clamped **3–8 fps** | can't become a fast, busy flip |
| Pose change | 300 ms cross-fade | no hard cuts / bounces / spins |
| Reduced motion | **all motion off**, static pose | wired to the child setting |
| Size | fixed height you pass | keep it identical everywhere |

## Preparing the art

1. Export each pose as a **transparent PNG** (remove the white background),
   trimmed tight to the character.
2. Source resolution **512–1024 px** on the long edge (Flutter downscales
   crisply; don't upscale small art).
3. Keep every pose the **same canvas size and anchor** so cross-fades and
   gesture frames don't drift.
4. Suggested layout:
   ```
   packages/shared_ui/assets/characters/
     bps_idle.png  bps_wave_1.png  bps_wave_2.png  bps_happy.png
     reiz_idle.png reiz_wave_1.png reiz_wave_2.png reiz_happy.png
   ```
   Register the folder under `flutter: assets:` in `shared_ui/pubspec.yaml`.

## Usage

Idle mascot with the gentle breathing:

```dart
CalmMascot(
  image: const AssetImage('assets/characters/bps_idle.png', package: 'shared_ui'),
  height: 260,
  reducedMotion: context.watch<ChildProvider>().reducedMotion,
  semanticLabel: 'BPs, your guide',
)
```

A calm wave on greeting (plays twice, then rests):

```dart
CalmMascot(
  image: const AssetImage('assets/characters/bps_idle.png', package: 'shared_ui'),
  gestureFrames: const [
    AssetImage('assets/characters/bps_wave_1.png', package: 'shared_ui'),
    AssetImage('assets/characters/bps_wave_2.png', package: 'shared_ui'),
  ],
  gestureTrigger: _waveToken, // increment to trigger a wave
  gestureFps: 6,
  gestureLoops: 2,
  reducedMotion: reducedMotion,
)
```

Switch emotion by swapping `image` (cross-fades automatically):

```dart
CalmMascot(image: happy ? bpsHappy : bpsIdle, reducedMotion: reducedMotion)
```

## Rules of thumb

- **Children:** idle + wave + happy only. Never the crying pose in a
  child-facing failure/break context (it models distress).
- **Always pass `reducedMotion`** from the child's setting.
- Animate on an event (greet, reward), then let it rest.
