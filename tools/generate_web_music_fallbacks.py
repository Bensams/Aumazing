"""Generate MP3 alternatives for browsers without Ogg Vorbis support.

Run before flutter build web. Files live in web/ so native APKs are unchanged.
Uses ffmpeg from PATH, or the locally installed imageio-ffmpeg package.
"""
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'packages/shared_audio/assets/audio'
OUTPUT = ROOT / 'apps/main_app/web/audio_fallback'


def main():
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    tracks = sorted((SOURCE / 'bgm').rglob('*.ogg'))
    tracks += sorted(SOURCE.glob('bg_music*.ogg'))
    for source in tracks:
        target = OUTPUT / source.relative_to(SOURCE).with_suffix('.mp3')
        target.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([
            ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
            '-i', str(source), '-codec:a', 'libmp3lame', '-b:a', '128k',
            str(target),
        ], check=True)
    print(f'Generated {len(tracks)} web music fallback tracks.')


if __name__ == '__main__':
    main()
