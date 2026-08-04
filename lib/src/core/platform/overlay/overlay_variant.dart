// Shared types for the multi-window overlay spike.
import 'package:flutter/material.dart';

/// The overlay's fixed visual variants. Callers pick a variant and pass
/// their own message; the overlay owns only the look of each variant:
/// [working] is the animated bars pill with the caller's label,
/// [info] is guidance on the primary pill, [error] alone renders red.
enum OverlayVariant { working, info, error }

/// Chroma key painted behind the overlay UI on Windows and keyed out by
/// SetLayeredWindowAttributes: everything this exact colour becomes
/// transparent AND click-through (Windows routes clicks on keyed pixels
/// to the window below). One blue-bit away from the pill fill (1F2230
/// vs 1F2231) on purpose: the capsule's antialiased edge pixels blend
/// toward the key colour and are NOT keyed out, so any residual fringe
/// is pill-coloured - an invisible outline. The pill interior (exactly
/// 1F2230) is never keyed. Linux needs no key (the X11 shape cuts the
/// window to the pill outline); macOS composits real per-pixel alpha.
const kChromaKey = Color(0xFF1F2231);

/// [kChromaKey] as a Win32 COLORREF (0x00BBGGRR).
const kChromaKeyColorref = 0x0031221F;
