"""Voice rosters and per-backend routing for the KIE path.

Two backends, selected with `--backend`:

  gemini      google/gemini-3-1-flash-tts  (default)
  elevenlabs  elevenlabs/text-to-speech-*  (currently failing upstream, see README)

Three age tiers give the app a real choice of narrator:

  adult  - grown-up narrator, the default for parent-facing and calm lines
  young  - teen / young-adult energy, closest to a peer voice
  child  - young-child character

The two backends reach those tiers very differently, and it matters:

  * Gemini takes a free-text `audio_profile` per speaker, so the age is stated
    outright ("a cheerful young child, about seven years old"). Real age
    control, no pitch tricks.
  * ElevenLabs offers fixed presets with no verified child voices, so its
    `child` tier is approximated from the brightest presets plus a local pitch
    shift. Tier labels there were curated from KIE's written descriptions, not
    by listening.

Either way: audition before adopting, and reorder these tables to taste.
"""

# ---------------------------------------------------------------- languages

LANGUAGES = {
    'en': dict(manifest='lines.csv', out='en',
               label='English', spoken='English'),
    'tl': dict(manifest='tagalog_lines.csv', out='tl',
               label='Filipino / Tagalog', spoken='Filipino (Tagalog)'),
    'ceb': dict(manifest='cebuano_lines.csv', out='ceb',
                label='Bisaya / Cebuano', spoken='Cebuano (Bisaya)'),
}

# ------------------------------------------------------------------ gemini

GEMINI_MODEL = 'google/gemini-3-1-flash-tts'

# Six slots: a woman and a man per age group. `voice_name` picks the timbre
# (these are Gemini's documented female/male voices); the age and gender are
# stated outright in audio_profile rather than left implied by the name, which
# is the only part the model reliably honours.
GEMINI_VOICES = {
    'adult': {
        'woman': ('Sulafat', 'warm'),
        'man':   ('Charon', 'informative'),
    },
    'young': {
        'girl': ('Autonoe', 'bright'),
        'boy':  ('Alnilam', 'firm'),
    },
    'child': {
        'girl': ('Leda', 'youthful'),
        'boy':  ('Alnilam', 'firm'),
    },
}

# Keyed by (tier, key) so gender is explicit in the prompt.
#
# Pitch is driven by this text far more than by voice_name -- measured, not
# assumed: the same Charon voice reads 188 Hz asked to speak "gently" and
# 125 Hz asked for a "deep, low-pitched voice". The first roster said "gently"
# for the men and landed every male slot inside the female range (188 / 239 /
# 291 Hz), which is why they read as girls. Naming the pitch explicitly is
# what fixes it. Measured results for the current wording:
#
#   man 125 Hz | teen boy 166 Hz | boy 214 Hz
#   woman 218 Hz | teen girl 213 Hz | girl 276 Hz
#
# The child boy is described as about ten rather than seven on purpose. Real
# seven-year-olds have the same pitch regardless of gender, so a truthful
# seven-year-old boy is indistinguishable from the girl; ageing him up is what
# makes the two child voices tellable apart.
GEMINI_PROFILE = {
    ('adult', 'woman'): 'A warm, patient adult woman in her thirties, '
                        'speaking to a young child',
    ('adult', 'man'):   'An adult man with a very deep, low, resonant male '
                        'chest voice, like a father speaking calmly to his '
                        'child',
    ('young', 'girl'):  'A friendly teenage girl about fifteen, warm and clear',
    ('young', 'boy'):   'A friendly teenage boy about fifteen, whose voice has '
                        'already broken, with a clear low-pitched male voice',
    ('child', 'girl'):  'A cheerful young girl, about seven years old',
    ('child', 'boy'):   'A cheerful boy about ten years old, with a boyish '
                        'voice that is noticeably lower than a girl\'s',
}

# Kept for the picker and for --list-voices.
GEMINI_TIER_PROFILE = {
    'adult': 'A warm, patient adult woman / man in their thirties',
    'young': 'A friendly, energetic teenage girl / boy',
    'child': 'A cheerful young girl / boy, about seven years old',
}

LABELS = {'woman': 'Woman', 'man': 'Man', 'girl': 'Girl', 'boy': 'Boy'}

# Manifest `emotion` -> Gemini style. Delivery for the whole library stays
# gentle; Promo/Hype is reserved for the celebration lines.
GEMINI_STYLE = {
    'calm': 'Empathetic',
    'gentle': 'Empathetic',
    'happy': 'Vocal Smile',
    'excited': 'Promo/Hype',
    'encouraging': 'Vocal Smile',
    'neutral': 'Vocal Smile',
}

# Style turned out to move pitch more than any other field -- measured on the
# same voice and profile: Vocal Smile 150 Hz, Empathetic 100 Hz, on identical
# short cues. Vocal Smile is what held the male slots up in the female range,
# so the male voices are pinned to Empathetic regardless of the line's emotion.
#
# The cost is real: male voices no longer get Promo/Hype on the celebration
# lines, so their praise is warm rather than exuberant. Sounding like the right
# gender matters more than sounding excited.
GEMINI_STYLE_PIN = {
    ('adult', 'man'): 'Empathetic',
    ('young', 'boy'): 'Empathetic',
    ('child', 'boy'): 'Empathetic',
}

# ------------------------------------------------------------- elevenlabs

MODEL_V2 = 'elevenlabs/text-to-speech-multilingual-v2'
MODEL_V3 = 'elevenlabs/text-to-dialogue-v3'

# Cebuano is not in Multilingual v2's language set; it is in Eleven v3's.
ELEVEN_LANG = {
    'en': dict(model=MODEL_V2, language_code='en', carrier=('Okay.', 'Ready.')),
    'tl': dict(model=MODEL_V2, language_code='tl', carrier=('Sige.', 'Handa na.')),
    'ceb': dict(model=MODEL_V3, language_code='ceb', carrier=('Sige.', 'Andam na.')),
}

# (voice_id, label, pitch_semitones) - pitch is applied locally after
# synthesis and only exists to approximate the child tier.
ELEVEN_VOICES = {
    'adult': {
        'bella':    ('hpp4J3VqNfWAUOO0d1Us', 'Bella - professional, bright, warm', 0.0),
        'tiffany':  ('6aDn1KB0hjpdcocrUkmq', 'Tiffany - natural and welcoming', 0.0),
        'allison':  ('1wGbFxmAM3Fgw63G1zZJ', 'Allison - calm, soothing, meditative', 0.0),
        'benjamin': ('LruHrtVF6PSyGItzMNHS', 'Benjamin - deep, warm, calming', 0.0),
        'mark':     ('UgBBYS2sOqTuMpoF3BR0', 'Mark - natural conversational', 0.0),
        'brian':    ('nPczCjzI2devNBz1zQrb', 'Brian - deep, resonant, comforting', 0.0),
    },
    'young': {
        'brittney': ('kPzsL2i3teMYv0FxEYQ6', 'Brittney - fun, youthful, informative', 0.0),
        'lucy':     ('lcMyyd2HUfFzxdCaC4Ta', 'Lucy - fresh and casual', 0.0),
        'hope':     ('uYXf8XasLslADfZ2MB4u', 'Hope - bubbly and girly', 0.0),
        'finn':     ('vBKc2FfBKJfcZNyEt1n6', 'Finn - youthful, eager, energetic', 0.0),
        'jamahal':  ('DTKMou8ccj1ZaWGBiotd', 'Jamahal - young, vibrant, natural', 0.0),
        'liam':     ('TX3LPaxmHKxFdv7VOQHJ', 'Liam - energetic, upbeat', 0.0),
    },
    'child': {
        'emma':  ('pPdl9cQBQq4p6mRkZy2Z', 'Emma - adorable and upbeat', 2.0),
        'anika': ('Sm1seazb4gs7RSlUVw7c', 'Anika - animated, friendly, engaging', 2.0),
        'kuon':  ('B8gJV1IhpuegLxdpXFOE', 'Kuon - cheerful, clear, steady', 2.0),
        'lutz':  ('9yzdeviXkFddZ4Oz8Mok', 'Lutz - chuckling, giggly, cheerful', 2.0),
    },
}

ELEVEN_TIER_SETTINGS = {
    'adult': dict(stability=0.55, similarity_boost=0.80, style=0.10, speed=0.95),
    'young': dict(stability=0.45, similarity_boost=0.78, style=0.25, speed=1.00),
    'child': dict(stability=0.40, similarity_boost=0.75, style=0.35, speed=1.00),
}

# v3 only. v2 has no audio tags and would read the brackets aloud.
ELEVEN_EMOTION_TAGS = {
    'calm': '[calmly]',
    'happy': '[cheerfully]',
    'excited': '[excited]',
    'gentle': '[gently]',
    'encouraging': '[warmly]',
    'neutral': '',
}

# ------------------------------------------------------------------- api

BACKENDS = ('gemini', 'elevenlabs')
TIERS = ('adult', 'young', 'child')


def roster(backend):
    return GEMINI_VOICES if backend == 'gemini' else ELEVEN_VOICES


def model_for(backend, lang):
    return GEMINI_MODEL if backend == 'gemini' else ELEVEN_LANG[lang]['model']


def resolve(backend, tiers=None, keys=None):
    """(tier, key, voice, label, pitch) for the requested selection.

    Keys repeat across tiers ('girl' exists as both young and child), so a
    selector may be either a bare key or a qualified 'tier/key'.
    """
    table = roster(backend)
    out = []
    for tier in (tiers or TIERS):
        if tier not in table:
            raise KeyError('unknown tier %r (have: %s)' % (tier, ', '.join(TIERS)))
        for key, entry in table[tier].items():
            if keys and key not in keys and '%s/%s' % (tier, key) not in keys:
                continue
            if backend == 'gemini':
                voice, character = entry
                label = '%s (%s, %s)' % (LABELS.get(key, key), voice, character)
                out.append((tier, key, voice, label, 0.0))
            else:
                vid, label, pitch = entry
                out.append((tier, key, vid, label, pitch))
    if keys:
        found = set()
        for tier, key, _v, _l, _p in out:
            found.add(key)
            found.add('%s/%s' % (tier, key))
        missing = [k for k in keys if k not in found]
        if missing:
            raise KeyError('unknown voice(s) for %s: %s'
                           % (backend, ', '.join(missing)))
    return out


def _gemini_input(lang, voice, text, tier, emotion, key=None):
    spoken = LANGUAGES[lang]['spoken']
    # Gemini has no language_code field -- it infers language from the text.
    # Naming the language in `scene`, and pinning the turn to the given line,
    # is what keeps short prompts from drifting into English or from having
    # the instructions themselves read aloud.
    scene = ('A warm children\'s learning app narrator speaks one short line in '
             '%s. Speak only the given line, in %s, and nothing else.'
             % (spoken, spoken))
    style = GEMINI_STYLE_PIN.get(
        (tier, key),
        GEMINI_STYLE.get((emotion or '').strip().lower(), 'Vocal Smile'))
    return {
        'temperature': 1,
        'scene': scene,
        'speakers': [{
            'speaker_id': 'Speaker 1',
            'voice_name': voice,
            'audio_profile': GEMINI_PROFILE.get((tier, key),
                                                GEMINI_TIER_PROFILE[tier]),
            'accent': 'Neutral',
            'style': style,
            'pace': 'Natural',
        }],
        'dialogue_turns': [{'speaker_id': 'Speaker 1', 'text': text}],
    }


def _eleven_input(lang, voice_id, text, tier, previous_text, next_text, emotion):
    cfg = ELEVEN_LANG[lang]
    settings = ELEVEN_TIER_SETTINGS[tier]

    if cfg['model'] == MODEL_V3:
        tag = ELEVEN_EMOTION_TAGS.get((emotion or '').strip().lower(), '')
        spoken = ('%s %s' % (tag, text)).strip() if tag else text
        return {
            'dialogue': [{'text': spoken, 'voice': voice_id}],
            'stability': settings['stability'],
            'language_code': cfg['language_code'],
        }

    inputs = {
        'text': text,
        'voice': voice_id,
        'language_code': cfg['language_code'],
        'stability': settings['stability'],
        'similarity_boost': settings['similarity_boost'],
        'style': settings['style'],
        'speed': settings['speed'],
    }
    # previous_text / next_text give the model prosodic context without
    # putting those words in the rendered audio -- the native fix for the
    # clipped, falling delivery bare one-word prompts otherwise get.
    if previous_text:
        inputs['previous_text'] = previous_text
    if next_text:
        inputs['next_text'] = next_text
    return inputs


def build_input(backend, lang, voice, text, tier, previous_text=None,
                next_text=None, emotion=None, key=None):
    """Backend-specific `input` payload for POST /api/v1/jobs/createTask."""
    if backend == 'gemini':
        return _gemini_input(lang, voice, text, tier, emotion, key)
    return _eleven_input(lang, voice, text, tier, previous_text, next_text, emotion)
