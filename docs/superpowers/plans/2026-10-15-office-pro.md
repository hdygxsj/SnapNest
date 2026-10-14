# Office Pro implementation plan

Goal: Add the four user-approved local office workflows to Qingyu Pro, in the existing panel.
Architecture: One Office tab with segmented subpages. Independent observable stores own persisted local data. Shared verified Pro entitlement gates mutations and exports; existing data remains readable. No server and no public release.
Tech stack: SwiftUI, AppKit, ImageIO, CoreGraphics, Foundation, existing StoreKit ProStore.

- [x] Tutorial: persistent projects and numbered image steps; import or capture, edit captions/order/remove/replace, reuse annotation canvas, export PDF and long PNG with bounded dimensions; atomic save and visible errors.
- [x] File shelf: security-scoped references, picker and file drops, missing-file indication, multi-file drag/copy, removal only removes references. Persist bookmarks and release access correctly.
- [x] Work scenes: named sets of app/folder/file/web references; capture running regular apps, manually add files and web URLs; one-click open, per-target failure reporting. Do not claim browser tabs or window positions restored.
- [x] Image comparison: import two images, fit without distortion, side-by-side and split slider, thresholded pixel differences; reject differing dimensions for difference rather than silently stretching; editable review note and export report.
- [x] Integration: Office page in existing top navigation, consistent system/light/dark theme, Pro panel links, capture-to-tutorial routing; no unlock bypass in production.
- [x] Verification: fixture tests for persistence/roundtrip/missing references, comparison pixels, tutorial exports and permissions gate; compile both release architectures, inspect rendered pages; document real permissions and purchase limitations.

Preserve existing uncommitted App Store preparation documents. No GitHub/Gitee push. Local private build only. User explicitly asked to implement all four, so execute without another design approval loop.
