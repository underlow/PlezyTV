# S9 — Панель плеера: дизайн

Основа — [концепция](concept.md) и [требования](requirements.md).

## 1. Обзор

Свой код в `lib/plezytv/tv_ui/player/`, подключение к Plezy через поиски в `TvUi` (возвращают `null`, когда
нужен вариант Plezy). Внешний слой контролов Plezy (`PlexVideoControls`) остаётся владельцем клавиш при
скрытой панели, маркеров и автопропуска, монтирования, затухания и автоскрытия, внешней цепочки «Назад».
Заменяем только то, что рисуется. Минимум повторённой логики и маленькие вставки.

## 2. Существующая система

- Экран плеера `VideoPlayerScreen` (`lib/screens/video_player_screen.dart`, 3120 строк, не правим); его part
  `lib/screens/video_player/parts/build.dart` собирает `Video(controls: PlexVideoControls…)` и стек наложений
  `VideoPlayerPlayNextOverlay`, `VideoPlayerStillWatchingOverlay`, `VideoPlayerBufferingOverlay`
  (`lib/screens/video_player/widgets/player_prompt_overlays.dart`), Watch Together. Ошибку рисует
  `_buildPlaybackFailure` там же.
- `PlexVideoControls` (`lib/widgets/video_controls/video_controls.dart` + parts): на TV строит
  `DesktopVideoControls` в `parts/navigation.dart`; кнопку пропуска `SkipMarkerButton`
  (`widgets/skip_marker_button.dart`) в `parts/markers.dart`; фокус на неё при маркере — `markers.dart`, если
  не открыт лист `OverlaySheetController`; снимает панель с экрана, когда она скрыта; собирает
  `TrackControlsState` (`models/track_controls_state.dart`) — значения и действия дорожек, качества, формата,
  синхронизации.
- Готовое в Plezy: перемотка удержанием — накопитель и `steppedSeekMultiplier` (`lib/media/stepped_seek.dart`),
  превью — `thumbnailDataBuilder` / `ScrubFrame`, `FinishTimeBuilder`, подписи `TrackLabelBuilder`,
  `SleepTimerService`, `PlayerSyncOffsets`, `SettingsService`; лист `VideoSettingsSheet` и поиск субтитров
  через `OverlaySheetController`.

## 3. Архитектура

Места встройки — по 1–3 строки, только вызов `TvUi` и запасной вариант Plezy:

| Место | Файл (строк) | Наш виджет | Для |
|---|---|---|---|
| H1 | `lib/widgets/video_controls/parts/navigation.dart` (172) | `TvPlayerPanel` вместо `DesktopVideoControls` | R4–R16 |
| H2 | `lib/widgets/video_controls/widgets/skip_marker_button.dart` (134) | `TvSkipButton` | R17 |
| H3 | `lib/widgets/video_controls/parts/markers.dart` (287) | проверка «панель владеет пультом» перед фокусом на кнопку пропуска | R11a, R17 |
| H4 | `player_prompt_overlays.dart` (790), `VideoPlayerPlayNextOverlay.build` | `TvUpNextCard` | R19 |
| H5 | там же, `VideoPlayerBufferingOverlay.build` | `TvBufferingDots` | R20 |
| H6 | `lib/screens/video_player/parts/build.dart` (386), `_buildPlaybackFailure` | `TvPlaybackError` | R21 |
| H7 | там же, стек наложений | `TvPauseIndicator` | R18 |

Все места срабатывают, только если `TvUi.enabled` и видео не Live TV (R1); решение — по данным, которые
у места уже есть.

`TvPlayerPanel` — фокусная область со своими режимами (полоса, кнопки, иконки, очередь, правая панель).
Получает всё, что получал `DesktopVideoControls`, плюс из `PlexVideoControls` `canControl`,
`canNavigateMediaItems`, `playbackPromptOpen` и признак офлайна. Внутри: шапка, нижняя полоса, ряд
play/⏮/⏭, иконки, ряд очереди `TvPlayerQueueRow`, правая панель `TvPlayerSidePanel`.

Перемотка (R8): `TvPlayerPanel` повторяет обработку ←/→ на полосе из `DesktopVideoControls` — тот же
накопитель, ускорение и показ превью при удержании, через общие части Plezy, а не копию. Перемотка при
скрытой панели остаётся у `PlexVideoControls`.

Правая панель — стек экранов («Настройки», «Субтитры», «Звук», «Качество», «Скорость», «Формат кадра»,
«Таймер сна», «Аудиовыход»); пункты из `TrackControlsState` и сервисов Plezy. «Ещё» открывает
`VideoSettingsSheet`, «Найти субтитры» — поиск Plezy, оба через `OverlaySheetController`; после закрытия
фокус возвращается в правую панель.

Права (R2) и офлайн (R3): флаги `canControl`, `canNavigateMediaItems`, офлайн и наличие колбэков/данных
(`onNext == null`, пустые версии, `thumbnailDataBuilder == null`) решают, что неактивно или скрыто. Своих
правил не вводим.

## 4. Состояние и владение

- Видимость панели и автоскрытие — `PlayerChromeController` (Plezy). Панель вызывает `onFocusActivity`;
  пока открыта правая панель (R11), она держит хром удержанием полосы контента
  (`setContentStripVisible(true)`, как полоса Plezy): `cancelAutoHide` не хватает — `onFocusActivity` и закрытие
  листов Plezy перезапускают таймер. Поэтому `contentStripVisible` значит «очередь или правая панель»; снятие
  признака снаружи (цепочка Назад, `hide()`) закрывает и правую панель. При закрытии удержание снимается.
- Режим внутри панели и стек правой панели — `TvPlayerPanel`; живут, пока панель на экране; при скрытии
  сбрасываются.
- Очередь открывается через `chromeController.setContentStripVisible(true)`, как полоса глав/очереди Plezy,
  чтобы внешняя цепочка «Назад» о ней знала.
- `TvPlayerSession` — общее состояние TV-плеера на один экземпляр `Player` (хранится вне панели, например
  через `Expando`, т.к. панель снимается с экрана при скрытии). Держит: память фокуса (R7) — id последнего
  элемента (не узел фокуса) и время скрытия, сброс при смене видео; флаг «следующее открытие — фокус на play»;
  признак открытой правой панели; узел фокуса иконок для кнопки пропуска. Читают панель, `TvSkipButton`,
  `TvPauseIndicator`.
- Фокус при появлении (R7): панель сама ставит фокус при монтировании — на play, если стоит флаг, иначе
  из памяти (если элемент доступен и прошло ≤ 30 с), иначе на полосу. Вызовы Plezy через ключ
  `_desktopControlsKey` для нас ничего не делают (D7).
- Пауза пультом (R5): `TvPauseIndicator` (H7) видит переход `playing → false` при скрытой панели, ставит флаг
  в `TvPlayerSession` и вызывает `chromeController.show()`. Индикатор паузы (R18) — тот же слой; 5 мин —
  от начала паузы.
- Очередь: панель слушает `chromeController.contentStripVisible` и закрывает ряд, когда Plezy снимает признак
  (Назад снаружи, скрытие). Свой накопитель перемотки панель сбрасывает при смене видео и при снятии с экрана.
- Кнопка пропуска (R17): H1 передаёт панели узел фокуса кнопки (`_skipMarkerFocusNode`) — ↑ с иконок на кнопку;
  `TvSkipButton` сам переводит ↓ на узел иконок из `TvPlayerSession` и учитывает открытую правую панель
  в своём положении. H3 — условие «на TV при видимой панели фокус не забирать» (`_showControls`).
- Подсказки (R11a): подсказка открыта, если `playNextFocusNode != null` (следующая серия) или
  `playbackPromptOpen` («Вы ещё смотрите?»). Пока подсказка открыта — состояние, а не только переход, — панель
  закрывает правую панель, снимает очередь (`setContentStripVisible(false)`), сбрасывает флаг «фокус на play»
  и сама невидима и инертна (без фокуса и обработки клавиш) независимо от `controlsVisible`: фокус на кнопке
  подсказки держит хром Plezy видимым (`PlayerChromeHold.promptInteraction`), поэтому `hide()` и возврат фокуса
  дают бесконечный цикл. `hide()` панель не вызывает и фокус не трогает — его ставит Plezy. Когда подсказка
  закрыта, панель снова следует `controlsVisible`.
- Назад внутри панели (R16, R22) — по протоколу TV-плеера Plezy: нажатие поглощается, действие по отпусканию,
  `BackKeyCoordinator.markHandled()`, как `handlePlayerNavigationKeyAction`.
- Буферизация (R20): панель читает `player.streams.buffering` и делает полосу неактивной.

## 5. Общие контракты

- Поиски `TvUi` — синхронные и дешёвые (`docs/plezytv/tv-ui.md`); аргументы — то, что место уже имеет;
  возвращают `Widget?` (H3 — `bool`).
- `TvPlayerPanel` использует колбэки Plezy как есть (`onPlayPause`, `onNext`, `onPrevious`,
  `onSeek`/`onSeekEnd`, `onQueueItemSelected`, `trackControlsState.*`); ошибки переключения и перезапуск при
  смене качества обрабатывает Plezy.
- `TvUpNextCard` и `TvPlaybackError` получают те же данные и узлы фокуса, что виджеты Plezy, поэтому фокус,
  отсчёт и Назад — по логике экрана Plezy (R19, R21, R22).

## 6. Решения

- **D1.** Подключаемся внутри `PlexVideoControls` (H1), а не вместо него: иначе повторять клавиши, маркеры,
  автопропуск, тосты, затухание. Принято: затемнение Plezy (0.7 сверху и снизу) остаётся, панель добавляет
  нижний градиент.
- **D2.** Индикатор паузы — отдельный слой в стеке экрана (H7): панель снимается с экрана при скрытии.
- **D3.** Кнопку пропуска поднимаем над иконками внутри своего виджета с учётом видимости панели: позицию задаёт
  большой `video_controls.dart`. Принято: возможен сдвиг в несколько пикселей от макета.
- **D4.** Вставка в `markers.dart` (H3) нужна, чтобы кнопка пропуска не забирала фокус у панели (R11a).
- **D5.** Карточка «Следующая серия» и ошибка — замена вида на месте (H4, H6), логика Plezy не трогается.
- **D7.** Панель не наследует `DesktopVideoControls` и не использует ключ `_desktopControlsKey`; его четыре
  метода (`requestPlayPauseFocus`, `abandonPendingSeek`, `dismissContentStrip`, `hideContentStrip`) заменены
  подписками панели (см. §4). Альтернатива — подтип `DesktopVideoControls`: ключ работал бы, но панель унаследовала
  бы внутреннее состояние и подписки панели Plezy и ломалась бы при их изменении. Подтверждено пользователем.
- **D8.** Обработка ←/→ на полосе (смена направления, счёт повторов, ограничение шага, показ превью, сброс при
  отпускании) копируется из `DesktopVideoControlsState` поверх общих `stepped_seek.dart` — она приватная.
- **D9.** H4 заменяет только содержимое карточки; оболочка Plezy (положение, PiP, удержание фокуса) остаётся.
- **D6.** Апстрим-мерж: дубли обязанностей (перемотка на полосе (D8), фокус, Назад внутри панели, замена методов
  ключа (D7)) — таблица
  в `tv-ui.md`, как в S12; предупреждение в PR мержа при изменении `desktop_video_controls.dart`,
  `markers.dart`, `player_prompt_overlays.dart`, `build.dart`, `navigation.dart`.

## 7. Потоки

1. **Открыть, перемотать, скрыть (R5, R7, R8).** OK при скрытой панели → `PlexVideoControls` показывает панель →
   `TvPlayerPanel` ставит фокус из памяти или на полосу. Удержание → → накопитель Plezy, превью из
   `thumbnailDataBuilder`; отпускание → одна перемотка. 5 с без нажатий → `PlayerChromeController` скрывает →
   память запоминает элемент.
2. **Субтитры (R11, R14, R16).** Иконка → правая панель, автоскрытие отменено. Выбор →
   `trackControlsState.onSwitchSubtitle`, отметка из нового состояния. Назад → закрыта, автоскрытие снова,
   фокус на иконке.
3. **Конец серии при открытой правой панели (R11a, R19).** Plezy показывает следующую серию → H4 рисует
   `TvUpNextCard`; `playNextFocusNode` → `TvPlayerPanel` закрывает правую панель и скрывает панель; фокус
   на «Смотреть», отсчёт и действие — Plezy.
4. **Маркер заставки (R17).** Plezy показывает кнопку → H2 рисует наш вид → H3: панель скрыта — фокус
   на кнопку, иначе нет.
5. **Пауза пультом (R5, R7, R18).** Play/Pause при скрытой панели → Plezy ставит паузу, панель не показывает →
   H7 видит паузу, ставит флаг и показывает панель → панель монтируется, фокус на play. Назад → панель скрыта,
   индикатор паузы.
6. **Ошибка (R21).** Plezy строит `_buildPlaybackFailure` → H6 рисует `TvPlaybackError` с тем же текстом
   и `onRetry`.

## 8. Согласование

Подтверждено пользователем 2026-10-24; после ревью дизайна пересмотрено и подтверждено (D7–D9, §4). В план делегированы: сигнатуры поисков, совмещение типа ключа (H1),
где хранить память фокуса, раскладка файлов.

Пользователь 2026-10-24 делегировал координатору все решения до завершения S9. Так принято: §4 «Подсказки» —
панель при открытой подсказке инертна вместо `hide(ignoreHolds: true)` (ревью T2 показало цикл показа/скрытия);
Назад на иконках — на полосу, по таблице `player.md` (выбор пользователя); §4 — правая панель держит
автоскрытие удержанием полосы контента вместо `cancelAutoHide` (ревью T4).
