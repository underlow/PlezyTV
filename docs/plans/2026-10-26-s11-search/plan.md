# S11 — Поиск: план

Контракт: `specification.md` (R1–R12, A1–A26). Checkout `/Users/underlow/Projects/PlezyTV`, ветка
`flow/s11-search`. Правила экранов — `docs/plezytv/tv-ui.md`. Образцы: S15 (`home/tv_home_screen.dart` — карточки,
`MediaContextMenu`, Play/Pause через `home/tv_home_playback.dart`, `withFreshWatchState`; `home/tv_home_model.dart` —
отбор элементов хабов), S10 (`watchlist/tv_watchlist_preferences.dart` — хранение в области профиля), S16
(`components/tv_paged_grid.dart`, `tv_paged_source.dart`), S7/S8 (ряды «В ролях» в `show/tv_show_screen.dart` и
`movie/tv_movie_screen.dart`), S12 (`shell/tv_section_shell.dart`). Логика поиска Plezy — `lib/screens/search_screen.dart`,
`lib/mixins/debounced_media_search.dart`, `DataAggregationService.searchAcrossServers`, `lib/utils/search_relevance.dart`
(не править). Тесты — `test/plezytv/tv_ui/search/` (`pumpTvWidget` из `tv_theme_test_helper.dart`).

Правок апстрима нет. Если задача обнаруживает, что без правки апстрима нельзя, — `needs-decision`.

## 1. Подход

- `lib/plezytv/tv_ui/search/` — контроллер и история (T1), клавиатура (T2), экран: результаты (T4) и пустой экран
  (T5).
- `components/` — общая круглая карточка человека, S7/S8 переходят на неё (T3).
- Оболочка S12 — монтирование экрана, проверки интеграции, документация (T6).

## 2. Общие контракты

**C1. Контроллер (T1 → T4, T5).** `TvSearchController` (`ChangeNotifier`), один на экран, без виджетов и
`BuildContext`. Зависимости — в конструктор:
- `TvSearchFn` = `Future<SearchAggregationResult> Function(String query, AbortController abort)`. Нет подключённых
  серверов — функция бросает `TvSearchUnavailable` (как `_SearchUnavailableException` в `SearchScreen`;
  `searchAcrossServers` без клиентов возвращает пустой результат без сбоев, поэтому проверка
  `hasConnectedServers` — в функции). Боевая функция (T4): `HiddenLibrariesProvider.ensureInitialized()` до первого
  запроса, затем `MultiServerProvider.aggregationService.searchAcrossServers` с `hiddenLibraryKeys`, как
  `SearchScreen.performSearchQuery`.
- `TvFetchItemFn` — перечитать элемент с сервера (как `SearchScreen.updateItem`, с `mergeFetchedMediaItem`).

API:
- `String get query`; `void setQuery(String)` — таймер 300 мс; пустой — сразу `idle`, отмена идущего.
- `void searchNow()` — без задержки (история, ссылка, пульт-компаньон, «Повторить», prime/resume, скрытие
  библиотеки); при пустом запросе ничего.
- `void clear()` — пустой запрос, сброс результатов и вкладки.
- Состояние: `idle`, `loading` (прежних результатов нет), `results`, `empty` (ничего из учитываемых типов),
  `unavailable` (`TvSearchUnavailable`, все серверы в `failedServerIds`, или успешных нет и есть отменённые — как
  `SearchScreen`; прочие ошибки — тоже `unavailable` с текстом Plezy `t.errors.searchFailed`).
  `bool get showSkeleton` — `loading` дольше 300 мс (таймер контроллера). При уточнении прежнее `results` остаётся
  до ответа (`bool get refining`).
- `String get shownQuery` — запрос показанных результатов (история, текст «Ничего не найдено»).
- `int get partialFailureRevision` — растёт на каждый ответ, где часть серверов не ответила (экран показывает
  сообщение один раз на ревизию).
- Типы: `movie`, `show`, `episode` и люди; ранжирование `rankMediaSearchResults` / `rankPeopleSearchResults` с
  `defaultMediaSearchLimit` на тип; `allOf(kind)` — ранжированный список (он же сетка вкладки), `rowOf(kind)` —
  первые 20 из него, `countOf(kind)` = `allOf(kind).length` (заголовок ряда показывает это число).
- Вкладки: `tabs` (`all`, `movies`, `shows`, `episodes`, `people`; только непустые, `all` всегда при `results`),
  `selectedTab`, `selectTab`. Вкладка сохраняется при новом ответе, если непуста, иначе `all`.
- `Future<void> refreshItem(MediaItem)` — заменить во всех списках.
- Устаревшие ответы отбрасываются по поколению, идущий поиск отменяется при смене запроса; `dispose` отменяет всё.

**C2. История (T1 → T4, T5).** `TvSearchHistoryStore` с `load()`/`save(List<String>)`; реализация в области
активного профиля через `StorageService` (`user_<scope>_plezytv_search_history`, scope читается при каждом
`load`/`save`, как у S10) и in-memory для тестов. `TvSearchHistory.add(list, query)` — чистая функция: обрезка
пробелов, пустое не добавляется, повтор без учёта регистра убирается, новый первым (последнее написание), не
больше 10. Раскладка клавиатуры — `StringPref('plezytv_search_keyboard_layout')` в `TvSettings` (на устройство),
значения `ru`, `en`, `digits`, по умолчанию `ru`.

**C3. Клавиатура (T2 → T4).** `TvSearchKeyboard` — без собственного состояния запроса:
- вход: раскладка, `onLayoutChanged`, `onInput(String)`, `onBackspace()`, `onClear()`, `onExitLeft()`,
  `bool onExitRight()` (ушёл ли фокус; если нет — фокус остаётся);
- `TvSearchKeyboardState.focusLastKey()` — последняя нажатая клавиша или первая клавиша текущей раскладки;
  `focusFirstKey()`; `bool get hasFocus`;
- раскладки по R2, пустые клетки не фокусируются, удержание ⌫ — повтор, токены `keyboard`, `design-system.md` §5.11;
- ввод с аппаратной клавиатуры и `adb shell input text`: печатаемые `character` событий клавиш при фокусе в
  клавиатуре — в `onInput`, Backspace/Del — в `onBackspace`; клавиши активации (Enter, Select, пробел-как-OK) не
  дают двойного действия: пробел вводит пробел, Enter/Select только нажимают клавишу в фокусе. Без системной
  клавиатуры и `TextInputConnection`.

**C4. Карточка человека (T3 → T4).** `TvPersonCard` в `components/`: `client` (`MediaServerClient?`), `imagePath`,
имя, подпись (необязательна), `focusNode`, `onSelect`. Круглое фото (`OptimizedMediaImage`, `fallbackIcon:
Icons.person`), размеры как в рядах «В ролях» S7/S8 сейчас. Для результата поиска клиент —
`context.tryGetMediaClientForServer(person.serverId)`, как `person_search_row.dart`.

**C5. Экран (T4 → T5, T6).** `TvSearchScreen({key, TvSearchFn? searchForTesting, TvFetchItemFn? fetchForTesting,
TvSearchHistoryStore? historyForTesting})` — без параметров боевые функции. Оболочка строит `TvSearchScreen(key:)`;
тесты T6 подставляют экран с подделками через `TvSectionShell.sectionBuilderForTesting`.

## 3. Задачи

### T1. Контроллер поиска и история
Результат: C1 и C2 с unit-тестами в `test/plezytv/tv_ui/search/`. Входы: R4, R5, R8, R9, R12;
`search_screen.dart`, `debounced_media_search.dart` как образец. Зависимостей нет.
Проверки (fake-функция поиска, fake clock):
- «д», «дю», «дюн» с интервалом 100 мс — один вызов на «дюн» через 300 мс;
- ответ на «д» после ответа на «дюн» — не применяется;
- только альбомы и треки → `empty`; только люди → `results` с вкладкой `people`;
- вкладка `movies` сохраняется с фильмами и сменяется на `all` без них;
- `TvSearchUnavailable` → `unavailable`; все серверы в `failedServerIds` → `unavailable`; часть →
  `results` и рост `partialFailureRevision`;
- `showSkeleton` ложно через 200 мс и истинно через 350 мс без ответа;
- при уточнении прежние результаты видны, `refining` истинно, `showSkeleton` ложно;
- `countOf` равен длине сетки вкладки; `rowOf` не длиннее 20;
- `refreshItem` заменяет элемент в ряду и во вкладке;
- история: порядок, обрезка до 10, «Дюна»/«дюна» — один элемент в последнем написании, пустое не добавляется;
  смена scope между `save` и `load` даёт разные списки.

### T2. Клавиатура
Результат: C3 с widget-тестами. Входы: R2, R3, R10 (фокус внутри клавиатуры), `design-system.md` §5.11,
`tokens.json → keyboard`, `05-search-*.png`. Зависимостей нет.
Проверки:
- РУС: 33 буквы, «-», «0–9», служебные, переключатель; OK по «Д» — `onInput` с «д» (регистр — на усмотрение,
  одинаково для всех путей ввода); «0–9» переключает на 123 и вызывает `onLayoutChanged`;
- → с правой колонки вызывает `onExitRight`, ← с левой — `onExitLeft`; пустые клетки пропускаются;
- `focusLastKey` после нажатия «Н» — фокус на «Н»; без нажатий — первая клавиша раскладки;
- удержание ⌫ — несколько `onBackspace`; «Очистить» — `onClear`;
- аппаратные `KeyA` → `onInput('a')`, пробел → `onInput(' ')` ровно один раз, Enter на клавише «Б» — один
  `onInput('б')`;
- клавиша 64×64 и зазор 12 в design px.

### T3. Общая карточка человека
Результат: C4; ряды «В ролях» S7 и S8 используют `TvPersonCard`. Входы: `show/tv_show_screen.dart`,
`movie/tv_movie_screen.dart`. Зависимостей нет. Сохранить размеры, подписи, переход в фильмографию.
Проверки: тест компонента — размер фото и место подписи равны прежним рядам S7/S8 (числа из их текущего кода),
подпись скрыта при `null`, `onSelect` по OK; существующие тесты S7/S8 проходят.

### T4. Экран поиска: результаты
Результат: `TvSearchScreen` (C5) с клавиатурой слева и правой колонкой для `results`, `loading`, `empty`,
`unavailable`; R1, R5, R6, R8, R9 (запись), R10, R11, экранная часть R12. Для `idle` правая колонка пока пустая
(её делает T5). Зависит от T1–T3.
- Возможности: `SearchInputFocusable` (`focusSearchInput` — фокус на клавиатуру; `submitSearchQuery` — подставить,
  `searchNow`, фокус по R10), `Refreshable.refresh` и `primeRefresh` — `searchNow` без очистки, `fullRefresh` —
  `clear` и перечитать историю для нового профиля (незавершённое чтение прежнего профиля отбрасывается),
  `FocusableTab.focusActiveTabIfReady` — по R10, `TabVisibilityAware.onTabHidden` — запись истории.
- Подписка на `HiddenLibrariesProvider` (после `ensureInitialized`): смена набора скрытых — `searchNow` при
  непустом запросе, как `SearchScreen._onHiddenLibrariesChanged`.
- Запись истории (R9): `onTabHidden`; Back с клавиатуры; `AppLifecycleState.paused`; любой маршрут, накрывший
  экран (`RouteAware.didPushNext` через `RouteObserver` профиля, как у оболочки) — это покрывает открытие результата
  и ссылки на элемент или фильтр. Записывается `shownQuery`, только при `results`.
- Карточки результатов: как `TvHomeScreen` (`TvPoster` / `TvEpisode` / `TvPersonCard`, `MediaContextMenu`,
  Play/Pause через `TvHomePlayback`, `withFreshWatchState`), но OK — `navigateToMediaItem(context, item,
  onRefresh: controller.refreshItem, playDirectly: false)`, чтобы эпизод следовал `episodeAction`. Подпись: год
  или число сезонов, при нескольких серверах — имя сервера, как `FocusableMediaCard` (`showServerName`).
- Вкладки — `TvTabs`; «Все» — `TvHorizontalRow` с `itemKey` = `globalKey`; вкладки типов — `TvPagedGrid` над
  `TvPagedSource` с готовым списком (`replaceAll(keepFocus: true)`, `keyOf` = `globalKey`). Общие компоненты не
  менять. После нового ответа экран сам проверяет фокус: элемент в фокусе пропал из своего ряда или сетки (готовые
  компоненты в этом случае ставят соседний индекс) или пропал весь ряд — фокус на первую карточку; результатов не
  осталось — на клавиатуру (`focusLastKey`).
- Состояния R8: скелетоны по `showSkeleton`; «Ничего не найдено» — текст с `shownQuery` (ряды под ним добавит T5);
  «Поиск недоступен» и «Повторить» (`searchNow`); сообщение о неполных результатах
  `showAppSnackBar(t.messages.searchPartialResults)` по `partialFailureRevision`.
Проверки (подделки C5):
- A3, A4, A5, A6, A11, A23, A26; A12-сценарий на экране: `submitSearchQuery('matrix')` — фокус на первом
  результате, ← — первая клавиша раскладки;
- A24: фокус на третьем фильме, повтор поиска без него — фокус на первой карточке; повтор без результатов — фокус
  на клавиатуре; повтор с ним — фокус на нём;
- `primeRefresh` с «дюн» — поиск повторён, текст не стёрт (A18); `fullRefresh` — стёрт, история перечитана из
  нового scope (A16);
- запись истории: `onTabHidden` с результатами — есть, с «Ничего не найдено» — нет (A8, A9); `paused` — есть
  (A25); push маршрута поверх экрана — есть;
- эпизод с `episodeAction = details` — открывается карточка, по умолчанию — воспроизведение (A20, наблюдатели
  навигатора, как в `tv_home_screen_test.dart`); Play/Pause — воспроизведение;
- A22: действие меню вызывает `refreshItem`, карточка обновлена, фокус на ней;
- раскладка сохраняется в `TvSettings` и читается при новом монтировании (A14).

### T5. Экран поиска: пустой экран
Результат: правая колонка для `idle` и ряды под «Ничего не найдено» (R7, R8). Зависит от T4.
- «Недавние запросы» — малые вторичные кнопки с иконкой истории; OK — подставить и `searchNow`, фокус по R10.
- До двух хабов из `DiscoverProvider` с отбором `TvHomeModelBuilder` (кроме «Продолжить просмотр»); карточки и
  действия как на главной, включая её `playDirectly`. Под «Ничего не найдено» — те же ряды без истории.
- Загрузка `DiscoverProvider`: при монтировании, `primeRefresh` и `fullRefresh` экрана — `load()`, если хабы не
  загружены (начальное состояние или ошибка) и загрузка не идёт. Без серверов `load()` уходит в ошибку и сам не
  повторяется (повтор у главной — в её `primeRefresh`), поэтому повтор при подключении серверов обязателен.
  Скелетоны, пока грузится; при ошибке или без подходящих хабов блока нет.
- Фокус: → с клавиатуры — первый запрос истории или первая карточка рядов; без них фокус остаётся.
Проверки:
- A1, A8 (ряды под текстом), A10 (с результатами и без);
- провайдер в начальном состоянии — один `load()`; ошибка без серверов → `primeRefresh` при подключённых → ряды
  появились (A19); ошибка — ни рядов, ни скелетонов;
- хабы только «Продолжить просмотр» — блока нет.

### T6. Оболочка, интеграция, документация
Результат: `TvSectionShell` монтирует `TvSearchScreen` для `NavigationTabId.search` (не-TV по-прежнему
`SearchScreen` — оболочка только TV); раздел S11 в `docs/plezytv/tv-ui.md`; предупреждение в
`.github/workflows/plezytv-upstream.yml` для `lib/screens/search_screen.dart`, `lib/mixins/debounced_media_search.dart`,
`lib/services/data_aggregation_service.dart`;
`docs/plezytv/dev-tools.md` — при изменении поведения ссылок. Зависит от T5.
Проверки (реальный `TvSearchScreen` с подделками через `sectionBuilderForTesting`):
- пульт-компаньон `onSearchAction('matrix')` и ссылка `search?q=matrix` открывают раздел, в поле запрос, фокус на
  первом результате (A12, A13); «Перейти к поиску» из «Списка» открывает раздел;
- `handleContentIntent(initialLoad)` при открытом поиске с запросом не стирает его (A18);
- ссылка на элемент поверх поиска с результатами — запрос в истории;
- существующие тесты оболочки, ссылок и `tv_ui` проходят; весь `flutter test` и `flutter analyze` — без новых
  падений (известны 2 датозависимых теста Live TV).

## 4. Проверка всей фичи

После T6: полный `flutter test`, `flutter analyze`, сборка APK. На устройстве (если доступно, скиллом `tv`):
скриншоты пустого экрана, результатов и «Ничего не найдено» против `05-search-*.png` и `08-state-search-nothing.png`
с учётом отличий из спецификации §3; вручную A2, A7, A9, A12, A15, A20, A21, A22. Если устройства нет — отметить в
итоге как непроверенное.

## 5. Итог

Готов 2026-10-26 на ветке `flow/s11-search` (не смержен, не запушен; на TV не проверен).

Сделано: раздел «Поиск» оболочки TV — `TvSearchScreen` со своей клавиатурой (РУС / ENG / 123, ввод с аппаратной
клавиатуры и `adb`), поиск с задержкой 300 мс по всем серверам без скрытых библиотек, вкладки «Все» / фильмы /
сериалы / эпизоды / люди, состояния загрузки, «Ничего не найдено», «Поиск недоступен» с «Повторить», история
(10 запросов на профиль), пустой экран с недавними запросами и двумя хабами Discover, фокус по R10/R11 с
восстановлением после повторного поиска, пока раздел скрыт. Общая `TvPersonCard` (ряды «В ролях» S7/S8 перешли на
неё; кольцо фокуса теперь круглое) и общая карточка хаба `home/tv_home_card.dart` (главная и поиск). Правок апстрима
нет; `plezytv-upstream.yml` предупреждает об изменениях логики поиска Plezy. Документация — раздел S11 в
`docs/plezytv/tv-ui.md`.

Коммиты: T1 `6f493f93c`, T2 `e480f0dd4`, T3 `d8903d1e0`, T4 `a9a439e44`, T5 `421ab07e0`, T6 `fa5125c1a`; уточнение
спецификации (повторная загрузка Discover после ошибки) `f57f42dee`; исправления по ревью `0c6ae95a4`, `78040ce9a`.

Проверка на `78040ce9a`: полный `flutter test` — 8974 прошли, 7 пропущены; `flutter analyze` — без замечаний;
debug APK собран. Два круга независимого ревью (поведение; тесты и код) и целевое ревью последнего исправления —
без открытых замечаний.

Не проверено: устройства не было — скриншоты против `05-search-*.png` и `08-state-search-nothing.png` и ручные A2,
A7, A9, A12, A15, A20, A21, A22 не выполнялись; A15 (`adb shell input text`) покрыт только widget-тестом
аппаратного ввода. Приёмка этапа по скриншоту остаётся.

Принятые ограничения: (1) счётчик явного фокуса, отменяющий уже запланированное восстановление фокуса, не покрыт
отдельным тестом; (2) восстановление фокуса после нового ответа при видимом разделе ждёт два кадра и может
перебить явный «фокус в поле», пришедший в этом окне. Обе — узкие гонки по времени. Не исправлено по решению
пользователя: размер файла экрана (~1.2k строк), трёхзначный `externalFocus`, состояние отложенного восстановления
в двух полях, подделка скрытых библиотек фильтрует сама.
