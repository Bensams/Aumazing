# Aumazing Splash Screen Video Generation

## Summary

Successfully generated a new ASD-friendly splash screen video for Aumazing using the kie.ai API.

## Generated Files

1. **Aumazing_Splash_Screen_Generation.webm** (1.9 MB)
   - Video only version with the new Aumazing logo
   - Features gentle, calming animation suitable for kids with ASD
   - 4 seconds duration, 720p resolution

2. **aumazing_splash_with_audio.webm** (380 KB)
   - Complete splash screen with "Aumazing" voice-over
   - Uses Microsoft Edge TTS (en-US-AnaNeural - child-friendly voice)
   - Cheerful but not overwhelming audio (+10% rate, +20Hz pitch)
   - Optimized file size with VP9 video encoding

## Key Features (ASD-Friendly Design)

✓ **Gentle movements** - No sudden changes or rapid motion
✓ **No flashing** - Consistent, calm visual pace
✓ **Soft colors** - The colorful Aumazing logo with three characters
✓ **Predictable animation** - Smooth, clear transitions
✓ **Brief duration** - 4 seconds (not overwhelming)
✓ **Friendly voice** - Warm child voice saying "Aumazing"
✓ **Appropriate volume** - Cheerful but not overstimulating

## Scripts Created

### `scripts/generate_splash_video.py`
Generates the splash screen video using kie.ai's bytedance/seedance-2 model.

Usage:
```bash
cd E:/Projects/aumazing
source tools/voice_gen/.env  # Load KIE_API_KEY
python scripts/generate_splash_video.py
```

**Cost:** 164 credits per generation

### `scripts/add_splash_audio_edge.py`
Adds voice-over using Microsoft Edge TTS (free) and combines with video.

Usage:
```bash
cd E:/Projects/aumazing
python scripts/add_splash_audio_edge.py
```

**Requirements:** edge-tts, imageio-ffmpeg (already in project)

## Technical Details

- **Video Engine:** kie.ai bytedance/seedance-2
- **TTS Engine:** Microsoft Edge Neural TTS (en-US-AnaNeural)
- **Input:** tools/logo_gen/aumazing_logo_unified.png
- **Output Format:** WebM (VP9 video + Vorbis audio)
- **Resolution:** 720p (834x1112, 3:4 aspect ratio)
- **Frame Rate:** 24 fps
- **Duration:** 4 seconds

## Prompt Design (ASD-Friendly)

The video generation prompt emphasizes:
- Static locked camera (no zooming or panning)
- Gentle, calm movements
- No sudden changes or overwhelming effects
- Soft pastel colors
- Simple, clear, predictable animation
- Warm smile and kind eyes on characters
- Consistent gentle pace throughout
- Centered framing with character staying in place

## Next Steps

To use the splash screen in the app:
1. Update the splash screen configuration to reference:
   `packages/assets/videos/aumazing_splash_with_audio.webm`
2. Ensure the video player component respects sensory-friendly playback
3. Consider adding a "skip splash" option for users who prefer it

## Files Location

- Source logo: `tools/logo_gen/aumazing_logo_unified.png`
- Video (no audio): `packages/assets/videos/Aumazing_Splash_Screen_Generation.webm`
- Video (with audio): `packages/assets/videos/aumazing_splash_with_audio.webm`
- Generation scripts: `scripts/generate_splash_video.py`, `scripts/add_splash_audio_edge.py`

## Credits Used

- Video generation: 164 credits (kie.ai)
- TTS: Free (Microsoft Edge TTS)
- Total cost: ~$0.16 (based on standard kie.ai pricing)
