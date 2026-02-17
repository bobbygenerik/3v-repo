## 2024-05-23 - Accessibility in Flutter
**Learning:** Flutter's `IconButton` is accessible by default but requires a `tooltip` property to be useful for screen readers. `GestureDetector` on `Icon` is a common anti-pattern that strips semantics.
**Action:** Always prefer `IconButton` over `GestureDetector(child: Icon(...))` and ensure `tooltip` is set. Use `semanticLabel` for `Image` widgets that convey meaning.

## 2024-05-24 - Accessibility in Custom Buttons
**Learning:** Custom buttons built with `InkWell` and `Container` lack native semantics and tooltips, making them inaccessible to screen readers compared to `IconButton`.
**Action:** Wrap custom `InkWell` buttons in a `Tooltip` widget and ensure a meaningful `message` string is provided, especially for toggle states (e.g., 'Mute' vs 'Unmute').

## 2024-05-25 - Accessibility in Modal Sheets
**Learning:** Section headers in custom modal sheets (like `showModalBottomSheet`) often lack semantic meaning for screen readers, making navigation difficult.
**Action:** Wrap section header text in `Semantics(header: true, ...)` so users can navigate by headings within the modal.

## 2024-05-26 - Accessibility in Video Feeds
**Learning:** Video previews (like PIP) with complex interactions (double-tap to swap, drag to move) are completely invisible to screen readers if implemented with raw `GestureDetector`.
**Action:** Wrap `GestureDetector` in `Semantics` widget, mapping complex gestures (like double-tap) to the primary `onTap` semantic action, and providing clear `label` and `hint` text explaining the available interactions.

## 2026-01-27 - Custom Button Accessibility
**Learning:** Custom buttons built with `InkWell` or `GestureDetector` + `Container` often lack accessibility semantics. Wrapping them in a `Tooltip` widget is an easy way to provide both visual tooltips (for mouse/long-press) and semantic labels (for screen readers).
**Action:** When creating custom animated buttons, always include a `Tooltip` wrapper with a descriptive message.
