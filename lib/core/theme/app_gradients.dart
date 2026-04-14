import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppGradients {
  // ── Parent screen backgrounds ────────────────────────────────────────
  static const LinearGradient parentLavenderMint = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.lavenderLight, AppColors.background, AppColors.mintLight],
  );

  static const LinearGradient parentSkyButter = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.skyLight, AppColors.background, AppColors.butterLight],
  );

  // ── Child game screen backgrounds ───────────────────────────────────
  static const LinearGradient matchIt = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.mintLight, AppColors.skyLight, AppColors.lavenderLight],
  );

  static const LinearGradient copyMe = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.butterLight, AppColors.peachLight, AppColors.mintLight],
  );

  static const LinearGradient doWhatISay = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.lavenderLight, AppColors.mintLight, AppColors.butterLight],
  );

  static const LinearGradient myTurnYourTurn = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.skyLight, AppColors.lavenderLight, AppColors.peachLight],
  );

  // ── Button gradients ─────────────────────────────────────────────────
  static const LinearGradient primaryCta = LinearGradient(
    colors: [AppColors.primaryPurple, AppColors.mint],
  );

  static const LinearGradient success = LinearGradient(
    colors: [AppColors.mint, AppColors.mintLight],
  );

  static const LinearGradient warning = LinearGradient(
    colors: [AppColors.peach, AppColors.peachLight],
  );

  static const LinearGradient info = LinearGradient(
    colors: [AppColors.lavender, AppColors.primaryPurple],
  );
}
