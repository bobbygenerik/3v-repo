## 2024-05-22 - Periodic Timers on UI Thread
**Learning:** Running high-frequency timers (e.g., 30Hz) on the UI thread to "detect" lag or manage stabilization is an anti-pattern. It adds overhead to the very thread it's trying to monitor and can contribute to the performance issues it aims to solve.
**Action:** Use native frame metrics or low-overhead performance observers instead of polling loops on the main thread. Avoid "optimizations" that do nothing but log.
