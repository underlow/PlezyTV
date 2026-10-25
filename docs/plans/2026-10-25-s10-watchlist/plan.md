# S10 — Watchlist: план

Контракт: `specification.md` (R1–R15, A1–A34). Checkout `/Users/underlow/Projects/PlezyTV`, ветка
`flow/s10-watchlist`. Правила экранов — `docs/plezytv/tv-ui.md`. Образцы: S16 (`lib/plezytv/tv_ui/library/`,
сетка `components/tv_paged_grid.dart`, `tv_paged_source.dart`, панели `library/tv_library_panels.dart`,
предпочтения `library/tv_library_preferences.dart`), S15 (`home/tv_home_playback.dart`), S8
(`movie/tv_movie_screen.dart`), S12 (`shell/tv_section_shell.dart`, `shell/tv_shell_section.dart`). Тесты — в
`test/plezytv/tv_ui/` (`pumpTvWidget` из `tv_theme_test_helper.dart`). Логика каталога Plezy —
`lib/services/catalog/`, `lib/providers/catalog_sources_provider.dart`, карточка каталога Plezy
`lib/screens/catalog_item_detail_screen.dart` (образец слияния копий, подписей копий и трейлера; не править).

Правки апстрима — параметр в `lib/services/catalog/catalog_library_matcher.dart` (C1) и разбор `watchlistedAt` в
`lib/services/catalog/plex_catalog_source.dart` (T2b, решение пользователя после T2). Остальное —
fork-owned файлы. Если задача обнаруживает, что без другой правки апстрима нельзя, — `needs-decision`.

## 1. Подход

- `lib/plezytv/tv_ui/watchlist/` — служба наличия (T1), контроллер списка и предпочтения (T2), экран «Список»
  (T4), карточка каталога (T5).
- `components/tv_paged_grid.dart` — расширения сетки без изменения поведения S16 (T3).
- Оболочка S12 — раздел «Список» (T6).

## 2. Общие контракты

**C1. Матчер (T1).** `CatalogLibraryMatcher.match(CatalogItem item, {bool refreshIncomplete = false})`. При
`true` запись кэша, у которой есть `failed/cancelled/unqueriedServerIds`, не возвращается из кэша: серверы
опрашиваются заново и ответ сливается с прежними копиями тем же `_fold`. Полная запись (все ответили) при `true`
отдаётся из кэша как обычно (для «не найдено» действует TTL). Без параметра поведение прежнее. Тест на новый
параметр — рядом с существующими тестами матчера в `test/`.

**C2. Служба наличия (T1 → T2, T4, T5).** `TvWatchlistAvailability` (`ChangeNotifier`): одна на смонтированный
экран «Список», общая для всех источников (ключ включает источник), создаётся экраном, передаётся в конструктор
контроллера (C3) и в аргументы карточки (C4). Получает `CatalogLibraryMatcher` и `MultiServerProvider`.
- Ключ элемента — `'${item.source.name}/${item.entryIdentityKey}'`.
- Результат `check` из карточки (включая найденное по дополненной форме) записывается в службу под ключом
  исходного элемента, поэтому после возврата в сетку видна плашка и работает Play/Pause.
- `TvAvailability statusOf(CatalogItem)`: `pending` (не проверен ещё ни разу или идёт первая проверка),
  `found(List<MediaItem> copies, {bool complete})`, `notFound`, `unchecked`.
- `void setItems(List<CatalogItem>)` — новый полный список (заменяет очередь; результаты известных элементов
  сохраняются).
- `void prioritize(Iterable<CatalogItem>)` — видимые и ближайшие в начало очереди.
- `void sectionOpened()` — перепроверка `notFound` старше 10 минут (R8).
- `Future<TvAvailability> check(CatalogItem item, {CatalogItem? enriched, bool retry = false})` — для карточки:
  отдаёт известный результат или проверяет вне очереди; `enriched` проверяется тоже, копии сливаются (как
  карточка Plezy); `retry` — с `refreshIncomplete`.
- `bool get checking` — в очереди или в работе есть элементы (R9).
- Реакция на `MultiServerProvider`: только когда меняется `expectedServerIds` или в наборе серверов на связи
  появляется новый сервер (служба помнит прежний набор), в очередь ставятся элементы с неполным ответом
  (`unchecked` и `found(complete: false)`) с `refreshIncomplete: true`; элементы, уже стоящие в очереди или в
  работе, повторно не ставятся. Повторные уведомления с тем же набором серверов проверок не запускают.
- Ограничение: не больше 3 одновременных проверок (до ~15 запросов на сервер). Число — константа, можно менять.
- `dispose` отменяет очередь; ответы уже идущих запросов игнорируются.

**C3. Контроллер списка (T2 → T4, T6).** `TvWatchlistController` (`ChangeNotifier`), живёт пока смонтирован
экран.
- Состояние: `sources` (подключённые с watchlist, Plex первым, остальные в порядке Plezy), `source`, `phase`
  (`loading`, `ready`, `error`), `all` (полный список), `view` (после вкладки, фильтров, сортировки), `tab`
  (`all/movies/shows/onServer`), `sort` (`added/title/year/rating`), `filters` (жанры, десятилетия),
  `genreOptions`, `decadeOptions`, `hasMultipleSources`.
- Методы: `load()`, `retry()`, `selectSource`, `setTab`, `setSort`, `setFilters`, `backgroundRefresh()`,
  `fullReset()`, `itemRemoved(CatalogItem)`, `itemRestored(CatalogItem)`.
- Служба (C2) приходит в конструктор. Контроллер вызывает `availability.setItems(all)` при каждом изменении `all`
  (загрузка, перечитывание, удаление, возврат, смена источника). Вкладка `onServer` строит `view` по службе;
  контроллер слушает службу и пересобирает `view`.
- Каждое изменение `view` сопровождается видом изменения `TvWatchlistChange`: `reset` (смена источника,
  вкладки, сортировки, фильтров, первая загрузка — фокус на первую карточку) или `keepFocus` (наличие,
  фоновое перечитывание, удаление, возврат — фокус удерживается по ключу, C5).
- Предпочтения (источник, сортировка, вкладка, фильтры по источнику) — на профиль, в стиле
  `TvLibraryPreferencesStore` (интерфейс + реализация на хранилище, фейк в тестах).

**C4. Карточка каталога (T5 ↔ T4).** `TvCatalogItemArgs { CatalogItem item; CatalogSource source;
TvWatchlistAvailability availability; void Function(CatalogItem) onRemoved; void Function(CatalogItem)
onRestored; }`, маршрут `tvCatalogItemRoute(TvCatalogItemArgs) → PageRoute<void>`. Открытие копии —
`openWatchlistCopy(BuildContext, List<MediaItem> copies)` в T5: одна копия — `navigateToMediaItemDetails`,
несколько — меню копий (подписи как у Plezy: библиотека, сервер, качество), затем выбранная. T4 использует ту же
функцию для OK в сетке.

**C5. Сетка и источник в памяти (T3 → T4).**
- `TvPagedSource<T>.replaceAll(List<T> items, {required bool keepFocus})` — синхронно заменяет всё содержимое
  (все страницы загружены, `totalCount = items.length`, без промежуточных состояний и без перезагрузки страниц) и
  шлёт одно структурное уведомление с признаком `keepFocus`. Источник для списка в памяти создаётся один раз на
  экран и не пересоздаётся (пересоздание сбрасывает фокус в `didUpdateWidget`).
- Новые необязательные параметры `TvPagedGrid`:
  - `ValueChanged<(int first, int last)>? onVisibleRangeChanged` — после прокрутки и смены размера;
  - `ValueChanged<int>? onPlayPause` — физическая Play/Pause (`mediaPlayPause`, `mediaPlay`) на элементе;
  - `Object? Function(T item)? keyOf` — сохранение фокуса по ключу: сетка запоминает ключ элемента в фокусе
    до изменения; на `replaceAll(keepFocus: true)` находит его в новом содержимом, переставляет
    `focusedIndex` и компенсирует прокрутку, чтобы строка элемента осталась на том же месте экрана; если
    элемента нет — фокус на следующем по старому индексу, иначе на предыдущем. На `keepFocus: false` — фокус и
    прокрутка в начало, как при смене сортировки в S16.
- Без новых параметров и без `replaceAll` сетка и источник ведут себя как сейчас (S16).

## 3. Задачи

Порядок: T1, T2, T3 (независимы), затем T2b и T5 (нужен T1), T4 (нужны T1–T3 и T5), T6 (нужен T4).

### T1. Матчер и служба наличия

**Результат:** C1 и C2. **Входы:** спецификация R8, R9, R12; `catalog_library_matcher.dart`,
`multi_server_provider.dart` (`expectedServerIds`, статусы серверов), `data_aggregation_service.dart`
(`LibraryLookupResult`). **Зависимости:** нет.
**Сохранить:** поведение матчера без параметра; существующие тесты матчера.
**Проверки (`flutter test` на фейковом `MultiServerProvider`/матчере):**
- `refreshIncomplete` опрашивает заново неполную запись и сохраняет прежние копии; полную берёт из кэша —
  ловит возврат неполного ответа из кэша (A10, A11);
- приоритет: после `prioritize` эти элементы проверяются раньше остальных — ловит проверку в порядке списка (A4);
- не больше 3 одновременных `match` — ловит лавину запросов;
- статусы: копии + неответивший сервер → `found(complete: false)`; пусто + неответивший → `unchecked`; все
  ответили, пусто → `notFound` (A24, A32);
- выход сервера на связь перепроверяет `unchecked` и `found(complete:false)`, не трогает `notFound` и полные
  `found` (A11, A32);
- `sectionOpened` перепроверяет только `notFound` старше 10 минут (A12);
- повторные уведомления `MultiServerProvider` с тем же набором серверов не запускают проверок; появление
  нового сервера на связи ставит неполные элементы один раз (без дублей с уже стоящими в очереди) — ловит
  лавину перепроверок при подключении серверов;
- результат `check` по дополненной форме виден через `statusOf` исходного элемента;
- `check(enriched:)` сливает копии обеих форм; `retry` идёт с `refreshIncomplete`;
- после `dispose` поздние ответы не уведомляют.
`flutter analyze` чисто.

### T2. Контроллер списка и предпочтения

**Результат:** C3. **Входы:** R2, R4–R6, R13; `catalog_source.dart`, `catalog_sources_provider.dart`,
`catalog_watchlist_machinery.dart`, источники в `lib/services/catalog/`, `explore_provider.dart` (образец
задержки и поколений), `tv_library_preferences.dart`. **Зависимости:** T1 (для вкладки `onServer`; можно
писать параллельно против C2 с фейком).
**Содержание:**
- загрузка всех страниц `fetchRow(watchlist)` до 1000 элементов; ошибка любой страницы — `error`; лишнее
  отрезается;
- выбор источника: запомненный, если подключён, иначе Plex, иначе первый; отключение открытого — источник по
  умолчанию без перезаписи запомненного; замена объекта источника в провайдере — переподписка;
- сортировки R5: `added` — по `addedAt` новые первыми, элементы без даты — в порядке источника после
  датированных; если ни у кого даты нет — порядок источника, развёрнутый для источников, про которые по их
  коду или API известно, что они отдают старые первыми (проверить MAL и AniList, у которых `addedAt` нет, и Plex);
  остальные сортировки — по R5, без значения в конце;
- **Plex: дата и жанры.** Проверить по коду Plezy и описанию API Plex Discover, есть ли у элемента watchlist
  дата добавления (`watchlistedAt` или аналог) и жанры, и в каком порядке Plex отдаёт список. Если поле есть —
  разобрать его в fork-owned коде из сырого ответа, если он доступен через `CatalogItem`/`MediaItem.raw`; если
  для этого нужна правка `plex_catalog_source.dart` или `plex_discover_client.dart` — `needs-decision` с
  предложением минимальной правки. Если подтвердить без живого ответа нельзя — оставить fallback R5 и записать в
  отчёт, что проверить на TV;
- фильтры: варианты из `all`; пустые разделы скрыты (R6); устаревшие сохранённые значения отбрасываются при
  загрузке; смена источника сбрасывает фильтры;
- изменения списка R13: подписка на `watchlistChanges`; после уведомления сравнение `all` с `isOnWatchlist` —
  `false` убирает элемент сразу; расхождение или новые члены — одно перечитывание через 1 с (дебаунс), без смены
  `phase`, ошибка перечитывания не меняет список; `ensureWatchlistLoaded` при загрузке и повтор при неудаче (до
  успеха, не чаще раза в 30 с); `itemRemoved/itemRestored` правят список сразу;
- `backgroundRefresh` (resume) и `fullReset` (сброс профиля) — по C3.
**Сохранить:** Explore и его предпочтение источника не меняются.
**Проверки (`flutter test` на фейковых источниках и провайдере):** порядок источников и запоминание на профиль
(A25, A26, A33); 1200 → 1000 (A31); ошибка страницы → `error`, `retry` загружает (A21); каждая сортировка и
«без значения в конце» (A14); фильтры + вкладка, скрытые жанры, отброс устаревшего (A15–A17); удаление через
`isOnWatchlist=false` и через `itemRemoved` убирает сразу, загрузка данных о составе без изменений не
перечитывает, двойное уведомление даёт одно перечитывание (A27, A28, A34); замена объекта источника —
уведомления нового объекта доходят. `flutter analyze` чисто.

### T2b. Дата добавления Plex

**Результат:** в `PlexCatalogSource._fromMetadata` (`lib/services/catalog/plex_catalog_source.dart`) у
`CatalogItem` заполняется `addedAt` из `metadata['watchlistedAt']`: целое (epoch-секунды, через `flexibleInt`) или
ISO-строка; иначе `null`. Минимальная правка, без смены запроса и прочих полей. **Входы:** R5; T2 (контроллер уже
сортирует по `addedAt`, без даты — порядок источника). **Зависимости:** нет.
**Сохранить:** остальные поля и запросы Plex; Explore и его порядок.
**Проверки:** тест рядом с существующими тестами `PlexCatalogSource` в `test/` — epoch-секунды и ISO-строка дают
`addedAt`, отсутствие поля даёт `null`. `flutter analyze` чисто.

### T3. Расширения сетки

**Результат:** C5 в `components/tv_paged_grid.dart` (и `tv_paged_source.dart`, если нужно). **Зависимости:** нет.
**Сохранить:** поведение S16 без новых параметров; тесты S16 (`test/plezytv/tv_ui/library/`, тесты сетки).
**Проверки (widget-тесты на `pumpTvWidget`, изменения только через `replaceAll`):** вставка двух элементов перед
фокусом с `keepFocus: true` — в фокусе тот же элемент, его строка на том же месте экрана (A13); удаление элемента в
фокусе — фокус на следующем, последнего — на предыдущем (A27); `keepFocus: false` — фокус и прокрутка в начало;
скелетон не появляется ни на одном `replaceAll`; `onVisibleRangeChanged` после прокрутки отдаёт видимые индексы; Play/Pause вызывает
`onPlayPause` с индексом в фокусе; без `keyOf` поведение как раньше (существующие тесты проходят).
`flutter analyze` чисто.

### T4. Экран «Список»

**Результат:** `TvWatchlistScreen` — раздел для оболочки: создаёт контроллер (C3) и службу (C2), шапка, вкладки,
панели источника/сортировки/фильтров (`TvRightPanel` как в S16), сетка с плашкой и подписью, скелетон, ошибка,
пустые состояния, OK и Play/Pause. **Входы:** R2–R11, R13, R14; макеты `06-watchlist.png`,
`08-state-empty-watchlist.png`, `07-state-loading-library.png`, `09-state-error-server.png`; токены S6.
**Зависимости:** T1, T2, T3; функция `openWatchlistCopy` и маршрут карточки из T5 — T4 вызывает их по C4 (если
T5 ещё не готов, T4 начинается после T5).
**Содержание:** плашка «На сервере» для `found`; подпись элемента — как Plezy подписывает элемент каталога
(`toMediaItem` и подписи карточек каталога), у найденного в фокусе — с префиксом «На сервере · »; вкладка
«Есть на сервере» — «Проверяем, что есть на сервере…», пока `checking` и пусто; видимый диапазон сетки →
`prioritize`; изменения `view` уходят в один `TvPagedSource` через `replaceAll` с `keepFocus` по
`TvWatchlistChange` (C3, C5); OK: `found` (в том числе неполный) → `openWatchlistCopy`, иначе маршрут карточки с
`onRemoved/onRestored` контроллера; Play/Pause на `found` — `TvHomePlayback.forContext` по образцу S15, с
`isCurrent`, который проверяет и что «Список» — текущий раздел оболочки, с первой копией; иначе ничего; возврат —
фокус на том же элементе (через `keyOf`); шапка на пустом экране и экране ошибки при нескольких источниках, ↑ с
кнопки действия — на кнопку источника. Тексты — в `tv_strings.dart` по образцу.
**Интерфейс для оболочки (T6 не правит код T4):** `TvWatchlistScreen` реализует `FocusableTab` (фокус на первую
карточку или кнопку действия), `TabVisibilityAware` (`onTabShown` → `sectionOpened` службы),
`Refreshable` (`backgroundRefresh`), `FullRefreshable` (`fullReset`); принимает `VoidCallback onOpenSearch` для
«Перейти к поиску».
**Сохранить:** компоненты S6/S16 без изменения внешнего вида.
**Проверки (widget-тесты с настоящими контроллером T2 и сеткой T3, фейковыми источниками и службой):** A3, A4
(приоритет видимых), A5, A6, A7, A13, A18, A19, A20, A21, A22, A23, A24 — по ожиданиям таблицы; составные пути:
A8/A27/A34 — после возврата из карточки или S8 с удалением элемента нет, фокус на соседнем, скелетона нет,
прокрутка на месте; A28 — возврат без изменений не перечитывает список; A12 — `onTabShown` вызывает
`sectionOpened`; A11/A32 — обновление службы даёт плашку в сетке, OK и Play/Pause работают на неполном `found`;
скелетон не показывается при ответе быстрее 300 мс; Play/Pause после смены раздела не запускает плеер.
`flutter analyze` чисто.

### T5. Карточка каталога

**Результат:** `TvCatalogItemScreen` и маршрут, `openWatchlistCopy` (C4). **Входы:** R10, R12; S8
(`movie/tv_movie_screen.dart` — шапка, кнопки, оценки), карточка каталога Plezy (дополнение через
`fetchDetail`, слияние копий, подписи копий, трейлер), `library_watchlist_candidates.dart`
(`mutateWatchlistMembership`). **Зависимости:** T1 (C2).
**Содержание:** шапка по R12; кнопка «Открыть» с местом всегда: `pending` — индикатор, неактивна (на
`DevicePerformance.isReduced` — статичный значок); `found` — активна, `openWatchlistCopy`; `notFound` — «Нет на
сервере», неактивна; `unchecked` — «Не удалось проверить», активна, OK — `check(retry: true)`. Фокус при
открытии — первая активная кнопка; смена состояния «Открыть» не двигает фокус и кнопки. «Убрать из списка» /
«Вернуть в список» через `mutateWatchlistMembership` для текущего источника, сразу (без ожидания данных о
составе); успех — `onRemoved/onRestored`; ошибка — сообщение как в Plezy, состояние кнопки прежнее. «Трейлер» —
как у Plezy (`_openExternalUrl`), только если есть.
**Проверки (widget-тесты):** A7, A8, A9, A10, A34 (вызов `onRemoved` до загрузки данных о составе), ошибка
удаления возвращает кнопку, меню копий при двух копиях (A6), «Трейлер» скрыт без ссылки. `flutter analyze`
чисто.

### T6. Раздел в оболочке и документация

**Результат:** раздел «Список» в `TvSectionShell`: идентичность в `TvShellSection`, пункт меню сразу после
библиотек (иконка закладки, как на `01`), доступность (связь + непустой `watchlistCapableSources`), ленивое
монтирование `TvWatchlistScreen`, шаги пульта-компаньона, восстановление после офлайна, переход на «Главную»
при недоступности, `handleContentIntent` (resume — `backgroundRefresh`, сброс профиля — `fullReset`), выбор
«Поиска» по запросу экрана. Обновить `docs/plezytv/tv-ui.md`: раздел «Список», правка матчера (C1), новые
параметры сетки (C5). **Входы:** R1, R14, R15; `tv_section_shell.dart`, `tv_shell_section.dart`,
`components/tv_side_menu.dart`, `test/plezytv/tv_ui/tv_section_shell_test.dart`. **Зависимости:** T4.
**Ловушка:** `TvShellSection` всегда несёт `tab`, и раздел «Нет связи» использует `discover` как заглушку. «Список»
так делать не должен: многие ветки `_current.tab == NavigationTabId.discover` (скрытие и показ «Главной»,
`refresh`, `didPopNext`, горячая клавиша обновления) приняли бы его за «Главную». Ключи, `IndexedStack`,
`TvSectionBuilder`/`sectionBuilderForTesting` и `_onScreen` построены на `NavigationTabId` — расширить их для
нового раздела (сигнатуру тестового построителя можно расширить, обновив существующие тесты).
**Сохранить:** все существующие разделы, их порядок, фокус и «Назад»; тесты оболочки.
**Проверки (тесты оболочки через `sectionBuilderForTesting`/фейки):** A1, A2, A29, A30; порядок пунктов
(библиотеки → «Список» → «Ещё»); шаг пульта проходит через «Список»; «Перейти к поиску» выбирает «Поиск»; выбор
«Списка» и возврат на него не вызывают хуков «Главной» (`onTabHidden/onTabShown/refresh` главной);
`onTabShown`/`Refreshable`/`FullRefreshable` экрана «Список» вызываются оболочкой.
`flutter analyze` чисто.

## 4. Проверка всего изменения

После T6 координатор: `flutter analyze`; `scripts/run_tests.sh` целиком (известные падения на базе —
датозависимые тесты Live TV `test/screens/livetv/guide_tab_test.dart`; сравнить с базой `92e7f01bd`).
Приёмка на TV (Xiaomi/Mi Box 4) по `06`/`08` и A1–A34 — у пользователя: скриншоты через ссылки S5, скорость
проверки наличия на реальном списке, дата добавления и жанры Plex.
