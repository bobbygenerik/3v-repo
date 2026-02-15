## 2024-05-22 - Missing Labels on Interactive Elements
**Learning:** Icon-only buttons (like password visibility toggles) often lack accessible labels or tooltips, making them confusing for screen reader users and mouse users who rely on hover states.
**Action:** Always add `tooltip` and/or `semanticLabel` to `IconButton`s and other icon-based interactive elements.

## 2024-05-24 - Mobile Form Accessibility
**Learning:** Flutter `TextField`s do not automatically support password managers or efficient keyboard navigation (e.g., "Next" vs "Done") unless explicitly configured with `AutofillGroup`, `autofillHints`, and `textInputAction`.
**Action:** Always wrap form fields in `AutofillGroup` and define specific hints and actions for each input to ensure a native-feeling experience.

## 2026-02-07 - Dynamic Tooltips for Call Controls
**Learning:** Call control buttons (Mute, Camera) often have static labels or none at all. Dynamic tooltips (e.g., "Mute microphone" vs "Unmute microphone") provide clearer feedback and accessibility than static "Mic" labels.
**Action:** Use conditional logic to swap tooltip strings based on the active state of the control.

## 2026-02-12 - Accessible Loading Buttons
**Learning:** When replacing button text with a `CircularProgressIndicator` during loading, screen readers often lose context or announce "disabled button" with no label.
**Action:** Wrap the `CircularProgressIndicator` (or other loading widget) in a `Semantics` widget with a descriptive `label` (e.g., "Signing in...") to maintain context during async operations.

## 2026-02-14 - Placeholder to Functional Micro-UX
**Learning:** Static "placeholder" buttons (like a favorite star that does nothing) degrade trust and perceived quality more than their absence. Implementing even basic client-side toggling (with haptic feedback) significantly improves the feeling of responsiveness and polish.
**Action:** Identify and activate static icon buttons using existing services (like `ContactService`) whenever possible, adding immediate visual and tactile feedback.

## 2026-02-15 - Enhancing Tap Feedback in Custom Widgets
**Learning:** `GestureDetector` lacks built-in visual feedback (ripple effect) and accessibility semantics, making custom interactive elements like reaction emojis feel unresponsive and invisible to screen readers.
**Action:** Replace `GestureDetector` with `InkWell` wrapped in a `Material` widget (even transparent) to provide ripple effects, and always wrap custom interactive elements in `Semantics` with a descriptive `label` and `button: true`.

## 2026-02-16 - Granular vs Global Loading States
**Learning:** Replacing full-screen blocking loading states with granular, contextual loading (e.g., button spinner, avatar overlay) significantly improves perceived performance and prevents jarring layout shifts.
**Action:** Always prefer localized loading indicators on the specific interactive element triggering the action over global "busy" overlays, unless the entire context must be blocked.

## 2026-02-18 - Semantics for Toggle Buttons
**Learning:** Custom toggle buttons (like tabs implemented as buttons) often lack screen reader context for their selected state, making navigation confusing.
**Action:** Wrap such buttons in `Semantics` with the `selected: true/false` property and a descriptive `label` to clearly communicate the active state and purpose.

## 2026-02-19 - Grouping Semantics for Compound Buttons
**Learning:** Common Flutter pattern of `InkWell` (Icon) + `Text` label below results in double announcement for screen readers ("Decline call button" then "Decline").
**Action:** Wrap the interactive element (`InkWell`) in `Semantics` with a comprehensive label, and wrap the separate `Text` widget in `ExcludeSemantics` to provide a single, clear focusable target.
