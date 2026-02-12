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
