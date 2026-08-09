/// Height in logical pixels of the strip the app draws across the top of every
/// child-mode game: the prompt bubble (upper left), the progress dots (upper
/// centre) and the retry / menu / parent-lock controls (upper right).
///
/// Games lay their content out *below* this strip. A game object underneath an
/// overlay is not merely untidy — the overlay eats the touch, so the child sees
/// a target they cannot reliably hit.
///
/// Games bias their layout down by this amount and only shrink their objects
/// when the remaining space genuinely cannot fit them: on a typical landscape
/// canvas there is slack below, so objects keep their full size and simply sit
/// lower. Shrinking a tap target is always the last resort.
const double kTopOverlayBand = 60;
