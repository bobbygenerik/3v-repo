## 2024-05-22 - Missing Labels on Interactive Elements
**Learning:** Icon-only buttons (like password visibility toggles) often lack accessible labels or tooltips, making them confusing for screen reader users and mouse users who rely on hover states.
**Action:** Always add `tooltip` and/or `semanticLabel` to `IconButton`s and other icon-based interactive elements.

## 2024-05-24 - Mobile Form Accessibility
**Learning:** Flutter `TextField`s do not automatically support password managers or efficient keyboard navigation (e.g., "Next" vs "Done") unless explicitly configured with `AutofillGroup`, `autofillHints`, and `textInputAction`.
**Action:** Always wrap form fields in `AutofillGroup` and define specific hints and actions for each input to ensure a native-feeling experience.

## 2026-02-07 - Dynamic Tooltips for Call Controls
**Learning:** Call control buttons (Mute, Camera) often have static labels or none at all. Dynamic tooltips (e.g., "Mute microphone" vs "Unmute microphone") provide clearer feedback and accessibility than static "Mic" labels.
**Action:** Use conditional logic to swap tooltip strings based on the active state of the control.
