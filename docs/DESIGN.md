---
version: alpha
name: TypeMate
description: Calm local dictation for desktop power users.
colors:
  primary: "#111827"
  secondary: "#4B5563"
  tertiary: "#5B6CFF"
  neutral: "#F8FAFC"
  surface: "#FFFFFF"
  success: "#16A34A"
  warning: "#F59E0B"
  danger: "#DC2626"
typography:
  h1:
    fontFamily: Inter
    fontSize: 2.5rem
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: "-0.03em"
  title:
    fontFamily: Inter
    fontSize: 1.25rem
    fontWeight: 650
    lineHeight: 1.3
  body-md:
    fontFamily: Inter
    fontSize: 1rem
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: Inter
    fontSize: 0.875rem
    fontWeight: 600
    lineHeight: 1.3
rounded:
  sm: 8px
  md: 14px
  lg: 22px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
components:
  button-primary:
    backgroundColor: "{colors.tertiary}"
    textColor: "#FFFFFF"
    rounded: "{rounded.md}"
    padding: 12px
  card-surface:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary}"
    rounded: "{rounded.lg}"
    padding: 24px
  status-success:
    backgroundColor: "{colors.success}"
    textColor: "#FFFFFF"
    rounded: "{rounded.sm}"
    padding: 8px
  status-warning:
    backgroundColor: "{colors.warning}"
    textColor: "#111827"
    rounded: "{rounded.sm}"
    padding: 8px
  status-danger:
    backgroundColor: "{colors.danger}"
    textColor: "#FFFFFF"
    rounded: "{rounded.sm}"
    padding: 8px
---

## Overview

TypeMate should feel like a quiet desktop utility that protects the user's flow. It is not a loud assistant brand and should not look like a chat product. The UI should communicate local privacy, readiness, and direct action.

## Colors

- **Primary `#111827`:** main text and high-contrast surfaces.
- **Secondary `#4B5563`:** supporting descriptions and metadata.
- **Tertiary `#5B6CFF`:** the single primary action accent for setup, preparation, and active controls.
- **Neutral `#F8FAFC`:** calm app background.
- **Success `#16A34A`:** ready and completed states.
- **Warning `#F59E0B`:** transcribing, setup, and recoverable attention states.
- **Danger `#DC2626`:** recording or blocking error states.

## Typography

Use a clean sans-serif direction. Flutter may fall back to system fonts until a bundled font is added. Text should be concise, direct, and readable on desktop screens.

## Layout

Prefer spacious cards and clear status areas. The app shell should show:

1. Current readiness or dictation phase.
2. The next useful action.
3. Minimal setup details such as microphone and shortcut.
4. Clear privacy/local messaging.

Avoid dense dashboards. TypeMate should be understandable at a glance.

## Shapes

Use rounded cards and controls, but avoid playful bubble shapes. The product should feel friendly, precise, and developer-ready.

## Components

- Primary button: one main action per view.
- Status dot or pill: communicate idle, listening, transcribing, inserted, or error.
- Listening overlay: compact, centered near the top of the screen, with a clear active recording indicator.
- Settings rows: simple label, current value, and edit control.

## Do's and Don'ts

Do:

- Keep the UI calm and low-friction.
- Use the accent color sparingly.
- Make local-only behavior clear.
- Show actionable errors for missing microphone, FFmpeg, or permissions.

Don't:

- Add account, cloud, or model-picker UI in v1.
- Hide recording state.
- Overload the home screen with technical runtime details.
- Use inconsistent colors for the same dictation phase.
