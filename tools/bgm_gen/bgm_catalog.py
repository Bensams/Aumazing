"""ASD-friendly background-music catalogue for the Aumazing games.

Every entry is instrumental, low-arousal and predictable. The design rules that
apply to *all* categories live in GLOBAL_STYLE_SUFFIX / NEGATIVE_TAGS so a track
can never drift into something startling.
"""

# Acoustic rules applied to every single track, regardless of category.
# Rationale is documented in the accompanying markdown catalogue.
GLOBAL_STYLE_SUFFIX = (
    "instrumental only, no vocals, steady unchanging tempo, very narrow dynamic "
    "range, no crescendo, no sudden accents, no startling transients, soft "
    "rounded attack, warm low-mid tone with rolled-off harsh treble, simple "
    "repeating motif, consonant harmony, gentle seamless loop, mixed quiet as "
    "background bed under speech"
)

# Hard API limit: negativeTags must stay under 200 characters, so this is the
# highest-value subset — the startle sources and the loud genres.
NEGATIVE_TAGS = (
    "vocals, lyrics, drums, percussion, cymbals, brass, distortion, crescendo, "
    "riser, drop, sudden dynamics, key change, tempo change, dissonance, "
    "sound effects, loud, aggressive, dramatic"
)
assert len(NEGATIVE_TAGS) <= 200, len(NEGATIVE_TAGS)

# Generation knobs: hold the requested style hard, allow almost no creative
# deviation (weirdness) so results stay predictable and on-spec.
STYLE_WEIGHT = 0.80
WEIRDNESS = 0.10
AUDIO_WEIGHT = 0.65
DURATION = 120
MODEL = "V5_5"

CATEGORIES = {
    "soft_relaxing": {
        "label": "Soft & Relaxing",
        "description": (
            "Lowest-arousal category. Sustained, slow, almost motionless. For "
            "children who are easily over-stimulated, or for winding down after "
            "a session."
        ),
        "prompts": [
            ("Felt Piano Rest",
             "extremely gentle solo felt piano, 60 BPM, soft sustained warm pad "
             "underneath, four-bar repeating motif in C major"),
            # Regenerated 2026-08-07. The original drifted into minor/suspense
            # colour and was reported as eerie. Sustained string pads do this
            # unless the key is pinned, so this one names it explicitly.
            ("Warm Strings Haze",
             "gentle warm string ensemble in C major, 58 BPM, soft sustained "
             "major triads, no vibrato, close and intimate, like a slow "
             "lullaby harmony, bright major key throughout, warm and "
             "consonant, reassuring"),
            ("Soft Harp Drift",
             "delicate solo harp arpeggios, 62 BPM, gentle reverb, simple "
             "repeating pattern, airy and weightless"),
            ("Quiet Guitar Room",
             "softly fingerpicked nylon acoustic guitar, 64 BPM, close and "
             "intimate, simple repeating chord cycle, no strumming"),
            ("Breathing Pad",
             "very slow ambient synth pad, 56 BPM, soft filtered sine tones "
             "swelling gently and evenly, meditative and continuous"),
        ],
    },
    "nature_ambient": {
        "label": "Nature & Ambient",
        "description": (
            "Soft tonal music layered with steady natural texture. The constant "
            "broadband texture masks unpredictable household noise, which many "
            "sound-sensitive children find easier than silence."
        ),
        "prompts": [
            ("Gentle Rainfall",
             "soft ambient pad with steady light rainfall texture, 60 BPM, "
             "warm low tones, calm and continuous, no thunder"),
            ("Morning Garden",
             "quiet ambient music with soft distant birdsong texture, 66 BPM, "
             "warm mellow keys, bright but very soft"),
            ("Slow Ocean",
             "calm ambient music with slow steady soft ocean wave texture, "
             "58 BPM, deep warm pad, no crashing waves"),
            ("Forest Light",
             "peaceful ambient music with faint leaf rustle texture, 62 BPM, "
             "soft mallet tones and warm pad, spacious and even"),
            ("Small Stream",
             "gentle ambient music with steady soft flowing water texture, "
             "64 BPM, light glassy tones, continuous and unchanging"),
        ],
    },
    "gentle_playful": {
        "label": "Gentle Playful",
        "description": (
            "Mildly energising without becoming stimulating. Slightly brighter "
            "and more rhythmic, for children who disengage when music is too "
            "still. Still no percussive transients."
        ),
        "prompts": [
            ("Happy Marimba",
             "soft marimba melody, 76 BPM, warm wooden tone, simple cheerful "
             "repeating pattern in a major key, light and even"),
            ("Bouncy Pizzicato",
             "gentle pizzicato strings, 78 BPM, playful but very soft, simple "
             "repeating major-key figure, light woodwind doubling"),
            ("Sunny Ukulele",
             "softly plucked ukulele, 80 BPM, warm and friendly, simple "
             "repeating major chord cycle, mellow tone"),
            ("Toy Xylophone Walk",
             "soft xylophone and glockenspiel melody, 74 BPM, sweet and simple, "
             "repeating nursery-style motif, cushioned mallets"),
            ("Little Whistle Tune",
             "soft whistled-style flute melody with light acoustic guitar, "
             "78 BPM, warm and friendly, simple repeating major melody"),
        ],
    },
    "lullaby_music_box": {
        "label": "Lullaby & Music Box",
        "description": (
            "Familiar, highly predictable nursery timbres. Strongest cue for "
            "'settle down' — useful for transitions, calm corners and the end "
            "of a play session."
        ),
        "prompts": [
            ("Music Box Circle",
             "soft music box melody, 62 BPM, sweet and simple, gentle "
             "repeating lullaby motif, warm bell tone"),
            ("Celesta Cradle",
             "soft celesta lullaby, 60 BPM, warm pad underneath, simple "
             "repeating rocking melody in a major key"),
            ("Kalimba Sleep",
             "soft kalimba thumb piano lullaby, 64 BPM, warm woody tone, "
             "simple repeating pattern, gentle reverb"),
            ("Humming Bells",
             "soft glockenspiel lullaby over warm sustained pad, 58 BPM, "
             "sparse and tender, slow repeating melody"),
            ("Cradle Piano",
             "gentle solo piano lullaby, 60 BPM, soft felt hammers, slow "
             "rocking three-beat feel, simple repeating melody"),
        ],
    },
    "focus_minimal": {
        "label": "Focus & Minimal",
        "description": (
            "Deliberately uneventful. A steady, near-static bed with almost no "
            "melodic 'events' to capture attention, so it supports on-task "
            "attention during matching, tracing and sorting activities."
        ),
        "prompts": [
            ("Steady Loop One",
             "minimal ambient music, 70 BPM, two soft alternating chords, "
             "very sparse gentle bell tones, hypnotic and unchanging"),
            ("Soft Pulse",
             "minimal soft synth pulse, 72 BPM, even eighth-note warm sine "
             "tones, one repeating pattern throughout, no melody"),
            ("Quiet Ostinato",
             "minimal piano ostinato, 68 BPM, one simple repeating figure "
             "throughout, soft and even, faint warm pad"),
            ("Even Ground",
             "minimal warm drone with slow soft mallet notes, 66 BPM, almost "
             "static, extremely consistent and predictable"),
            ("Patient Keys",
             "minimal electric piano, 70 BPM, soft repeating four-note pattern, "
             "warm mellow tone, no variation or development"),
        ],
    },
    "filipino_calm": {
        "label": "Filipino Calm",
        "description": (
            "Culturally familiar tone colours for Filipino families, kept "
            "within the same calm envelope as the other categories. Pairs with "
            "the app's Tagalog and Cebuano voice-overs."
        ),
        "prompts": [
            ("Kundiman Hush",
             "gentle Filipino kundiman-style melody, 62 BPM, soft nylon guitar "
             "and warm strings, tender and slow, simple repeating melody"),
            ("Soft Rondalla",
             "softly plucked Filipino rondalla bandurria and laud, 70 BPM, "
             "warm and mellow, simple repeating major melody"),
            ("Bamboo Breeze",
             "soft bamboo flute melody over warm pad, 64 BPM, airy and calm, "
             "simple repeating pentatonic motif"),
            ("Kulintang Calm",
             "very soft kulintang gong-chime pattern, 68 BPM, warm rounded "
             "mallets, gentle repeating cycle, no loud strikes"),
            ("Harana Evening",
             "gentle Filipino harana-style serenade instrumental, 66 BPM, soft "
             "nylon guitar with light strings, warm and slow"),
        ],
    },
}


def build_style(prompt_style: str) -> str:
    return f"{prompt_style}, {GLOBAL_STYLE_SUFFIX}"
