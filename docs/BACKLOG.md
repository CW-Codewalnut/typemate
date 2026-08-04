# Backlog

Ideas that earned a place but not a milestone yet. (The bootstrap-era
PLAN.md this survived from is in git history.)

- **Custom dictionary / vocabulary boosting**
  - Let users add custom words such as names, company terms, product
    names, acronyms, and technical vocabulary.
  - Store the dictionary locally.
  - Use the saved words as STT context/hotwords if the local runtime
    supports it.
  - Add a post-transcription correction pass for likely misheard custom
    words.
  - Consider future auto-suggestions from repeated user corrections.
- **Wayland support** via the portal APIs (global shortcut and text
  insertion are the blockers; see README's Linux notes).
- **macOS overlay driver verification**: the multi-window overlay
  shipped for Windows/Linux; the ObjC-FFI macOS driver exists but is
  untested (no Mac available), so macOS still uses the native Swift
  panel. Verify on real hardware, then retire the Swift overlay too.
- **Linux store distribution** (Snap/Flathub) — needs a real
  snapcraft/flatpak manifest written for the slim-install layout; the
  icons_launcher-generated snap/ scaffolding was removed as misleading.
  (Flathub would carry the free tier only if a paid tier ever ships.)
