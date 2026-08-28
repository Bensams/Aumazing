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

/// Height in logical pixels of the strip along the *bottom left* of a child-mode
/// screen where the app's mascot stands (92px of character plus the host's 12px
/// padding).
///
/// The mascot ignores pointers, so it never steals a touch — but it does paint
/// over whatever the game put there. A game that places a character or a card in
/// the lower-left corner should keep this much clearance, scaled down on a short
/// canvas where reserving the full band would cost more than the overlap does.
const double kBottomMascotBand = 104;
