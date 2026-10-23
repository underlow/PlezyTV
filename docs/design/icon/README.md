# PlezyTV — иконка и TV-баннер

**Концепция:** контур экрана телевизора с подставкой (акцент `#E5A00D`) и белый треугольник play
(`#F2F3F5`) на тёмном фоне `#0E0F12`. Оригинальная Plezy — оранжевый сплошной треугольник с волнами
на светлой подложке, так что рядом на лаунчере их не спутать: другая форма (экран, а не треугольник),
другой фон (тёмный) и TV-мотив. Толстые линии (5,5 dp) без мелких деталей читаются и в 48 px.
На баннере — знак и словесный знак «Plezy**TV**» (Manrope ExtraBold, «TV» акцентом).

| Файл | Что |
|---|---|
| `src/ic_launcher_foreground.svg` | Адаптивная иконка, передний слой 108×108 dp; рисунок в 26…82 × 30…82, внутри безопасных 66×66 (21…87) |
| `src/ic_launcher_background.svg` | Задний слой: сплошной `#0E0F12` (= `ic_launcher_background` в `colors.xml`) |
| `src/ic_launcher_monochrome.svg` | Монохромный слой (тематические иконки Android 13+), одним цветом |
| `src/ic_launcher_legacy.svg` | Обычная иконка: скруглённый квадрат, фон + знак |
| `src/tv_banner.svg` | TV-баннер 320×180 |
| `png/legacy/ic_launcher-{mdpi…xxxhdpi}-{48…192}.png` | Обычная иконка 48, 72, 96, 144, 192 px |
| `png/adaptive/ic_launcher_{foreground,background,monochrome}-432.png` | Слои адаптивной иконки, 432 px (xxxhdpi), прозрачный фон у переднего и монохромного |
| `png/banner/tv_banner-{xhdpi,xxhdpi,xxxhdpi}-{320x180,480x270,640x360}.png` | Баннер |
| `render.sh` | Пересобирает все PNG из `src/` через headless Chrome |

**Заметки для переноса в `android/`:**
- Для `drawable/ic_launcher_foreground.xml` и `ic_launcher_monochrome.xml` фигуры простые
  (скруглённый прямоугольник-контур, прямоугольник, треугольник) — переносятся в VectorDrawable 1:1,
  viewport 108×108.
- Текст в `tv_banner.svg` — живой шрифт Manrope ExtraBold. PNG уже отрисованы с ним. Если SVG
  нужно открывать без Manrope, переведите текст в кривые.
