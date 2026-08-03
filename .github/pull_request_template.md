<!-- For a release PR (dev -> main), this description becomes the
     release notes on the draft release, word for word. Write it for
     the people reading the Releases page. -->

## Summary

<!-- What this PR delivers and why. -->

## Changes

-

## Verification

<!-- Proof the changes work: test output, CI runs, screenshots.
     CI enforces formatting, the security scan, and the full
     unit + e2e suite on Windows, Linux, and macOS. -->

## Checklist — check off before requesting review

- [ ] Unit/widget tests cover the components and helpers I touched,
      including negative and edge cases.
- [ ] End-to-end coverage: the e2e suites in `integration_test/`
      exercise my change, or I extended them where the user-visible
      flow changed.
- [ ] I manually verified the change in the running app on at least
      one target OS (not just tests).
- [ ] Analyzer and formatter are clean; no lint issues suppressed
      without a comment explaining why.
- [ ] I removed dead code, debug leftovers, and non-descriptive
      comments from the files I touched.
- [ ] Every linked issue this PR claims to fix is actually resolved
      by it (verified, not assumed).
- [ ] Nothing visible is a placeholder: every control, tab, and
      metric added by this PR works.
- [ ] Docs (README / CLAUDE.md / docs/DESIGN.md) are updated where
      behavior or process changed.
- [ ] Release PRs only: version bumped in `pubspec.yaml`, and this
      description is written to serve as the release notes.

### If anything above is unchecked, explain why

...
