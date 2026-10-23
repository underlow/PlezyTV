# PlezyTV launcher artwork brief

Create a distinct PlezyTV identity for a public Android TV fork of Plezy. The icon
must be recognisable at small sizes and visibly different beside original Plezy.
Use a clear TV motif and a “PlezyTV” wordmark on the banner. Avoid fine detail.

Use `tokens.json`: background #0E0F12, accent #E5A00D, text #F2F3F5,
Manrope bold/extrabold. See `design-system.md` for the surrounding TV interface.
Provide editable SVG source and exported PNG assets, with no baked device frame.

Deliver:
- Adaptive launcher foreground and background separately, 108×108 dp; keep key
  artwork inside the central 66×66 dp safe zone. Supply a monochrome layer too.
- Legacy launcher PNGs: 48, 72, 96, 144, 192 px (mdpi through xxxhdpi).
- TV banner: 320×180 px at xhdpi, plus 480×270 and 640×360 px exports.
  The wordmark should remain readable from a sofa.

Placement: `android/app/src/main/res/mipmap-{density}/ic_launcher.png`,
`drawable/ic_launcher_foreground.xml`, `drawable/ic_launcher_monochrome.xml`,
`values/colors.xml` (`ic_launcher_background`), and
`drawable-{xhdpi,xxhdpi,xxxhdpi}/tv_banner.png`. Preserve alternate icon assets.

Until final art arrives, run `swift scripts/plezytv/make_placeholder_icons.swift`
on macOS from the repository root. It reads pinned upstream originals and adds
an amber TV badge to default legacy icons, adaptive foreground and banners.
The existing monochrome layer remains upstream artwork until final art arrives.
