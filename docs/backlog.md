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
- **Native overlay UI via a Flutter multi-window package** (replacing
  the per-platform overlay renderers) — feasibility gate: frameless +
  transparent + never-steals-focus on all three desktop OSes.
