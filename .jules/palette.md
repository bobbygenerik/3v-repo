## 2024-05-23 - Accessibility in Flutter
**Learning:** Flutter's `IconButton` is accessible by default but requires a `tooltip` property to be useful for screen readers. `GestureDetector` on `Icon` is a common anti-pattern that strips semantics.
**Action:** Always prefer `IconButton` over `GestureDetector(child: Icon(...))` and ensure `tooltip` is set. Use `semanticLabel` for `Image` widgets that convey meaning.
