# S7 — Страница сериала: дизайн

Контракт — [requirements.md](requirements.md) (H1–H17, A1–A16). Сведения о коде — чтение 2026-10-24, не сборка.

## 1. Обзор

Свой `TvShowScreen` в `lib/plezytv/tv_ui/show/`. Данные — вызовы публичного не-UI кода Plezy (клиент сервера,
`episode_collection.dart`, оценки, загрузки, действия просмотра, запуск плеера). Оркестрация экрана Plezy
приватна (`_MediaDetailScreenState`, `action_buttons.dart` — `part of` большого файла), поэтому своя.
Апстрим правится в одном месте — `navigateToMediaItemDetails` в `lib/utils/media_navigation_helper.dart`.

## 2. Существующая система

- `navigateToMediaItemDetails` (mnh) → `mediaDetailNavigationTargetFor` (эпизод/сезон → сериал +
  `initialSeasonIndex/Id`, `initialEpisodeId`) → `Navigator.push(mediaDetailRoute(...))` → `bool` «изменилось
  состояние просмотра» → `onRefresh`. Через неё идут `navigateToMediaItem`, карточки, меню «Подробнее»,
  ссылки S5 (`screen_link_router._openItem`).
- Клиент `MediaServerClient`: `fetchItemWithOnDeck` (у Plex — с эпизодом на очереди, у Jellyfin — null),
  `fetchChildren` (сезоны), `fetchSeasonEpisodesPage` / `fetchSeasonEpisodePage(client, show:, season:, …)`,
  `fetchChildrenPage`/`fetchPlayableDescendantsPage` (сплющенный режим), `fetchExtras`, `fetchRelatedHubs`;
  только у `PlexClient` (не в `MediaServerClient`): `getLibrarySectionPrefs` для `flattenSeasons` — контроллер
  ветвится по `client is PlexClient`, получение prefs внедряемо для тестов.
- `episode_collection.dart`: `preferredSeasonIndex`, `defaultPlaybackSeason`, `firstUnwatchedEpisode`,
  `firstUnwatchedSeasonIndex`, `isSpecialSeasonNumber`, `fetchFirstEpisodeForSeason`;
  `plex_season_display.dart`: `shouldShowPlexEpisodesDirectly`; Jellyfin сплющивает при ≤1 сезоне.
- Оценки: `mediaRatingsFor` + `withCommunityRatings` с потоком `CatalogSourcesProvider.communityRatingsForLibraryItem`.
- Кнопки: плеер — `navigateToVideoPlayerWithRefresh`/`navigateToVideoPlayer`; перемешать —
  `MediaListPlaybackLauncher.forItem`; просмотрено — `WatchActions.setWatched`; список —
  `CatalogSourcesProvider.watchlistCandidatesFor`, `mutateWatchlistMembership`, `showWatchlistSourceChooser`;
  скачать — публичный `queueDownloadWithFeedback` (`lib/utils/download_utils.dart`, внутри — диалог версии,
  синхронизации, ограничений сети) и состояние из `DownloadProvider`; «⋯» — `MediaContextMenu`.
  Человек — `navigateToPersonMedia`.
- Свои компоненты S6/S15/S16: `TvPoster`, `TvEpisode`, `TvMediaBadges`, `TvMediaProgress`, `TvButton`,
  `TvIconButton`, `TvChip`, `TvRatings`, `TvHero`, `TvHorizontalRow`, `TvTabs`, скелетоны,
  `TvTintedBackground`, `TvFocusable`, `TvTheme`, `tv_strings.dart`.

## 3. Архитектура

- **Точка подключения (D1).** В mnh `navigateToMediaItemDetails`:
  `TvUi.showDetailRoute(metadata:, isOffline:, initialSeasonIndex:, initialSeasonId:, initialEpisodeId:) ?? mediaDetailRoute(...)`
  после guard `isCatalogItem`, с аргументами из `target.metadata` и `target.initial*` (не из исходного `mi`)
  (≤3 изменённые строки + импорт). `TvUi.showDetailRoute` — синхронная, без I/O: не-null только при
  `enabled && !isOffline && metadata.kind == MediaKind.show`. Возвращает `PageRoute<bool>` с той же
  непрозрачной fade-анимацией, что `mediaDetailRoute` на TV. S8 добавит рядом `movie`.
- **`TvShowController`** (ChangeNotifier, без виджетов) — владеет данными: сериал, эпизод на очереди, сезоны,
  режим «сплющено», кэш эпизодов по сезону (постранично, `TvPagedSource`-подобно или списком страниц),
  трейлер/экстры, похожие хабы, оценки сообщества, кандидаты списка, флаг `watchStateChanged`. Все
  загрузки несут поколение; чужие ответы отбрасываются. Порядок: `fetchItemWithOnDeck` → параллельно
  сезоны(+prefs Plex), экстры, похожие, оценки, кандидаты. Запасной «на очереди» без сервера —
  `firstUnwatchedEpisode` по загруженному сезону по умолчанию, как Plezy. Чистые функции (метка главной
  кнопки, цель, выбор вкладки и эпизода для фокуса, строка метаданных) — в `tv_show_logic.dart` с тестами.
- **Главная кнопка (H7).** Цель = эпизод на очереди → иначе первый непросмотренный → если все просмотрены —
  «Пересмотреть» = первый эпизод `defaultPlaybackSeason` с начала (`viewOffset` игнорируется, запуск с 0) →
  иначе «Смотреть S1 E1» через `fetchFirstEpisodeForSeason`. «Пересмотреть» — когда нет эпизода на
  очереди и `firstUnwatchedEpisode` по обычным (не `isSpecialSeasonNumber`) сезонам ничего не находит;
  цель — `fetchFirstEpisodeForSeason(defaultPlaybackSeason)` с позиции 0. Отличие от Plezy: на TV Plezy берёт эпизод в фокусе рельса — у нас
  кнопка на вкладке «Сериал», где рельса эпизодов нет, поэтому всегда «на очереди».
- **`TvShowScreen`** — хост: фон `TvTintedBackground` (сериал на «Сериал», кадр эпизода в фокусе на сезоне,
  с отложенной сменой как в `TvHero`), шапка (логотип/название, строка метаданных), `TvTabs`, содержимое
  вкладки, вертикальная прокрутка вкладки «Сериал» к рядам по правилу `tv-ui.md`.
  - `TvShowOverview` — жанры (`TvChip`), `TvRatings`, описание, ряд кнопок `TvShowActions`, ряд сезонов,
    ряды «В ролях», «Трейлеры и дополнительно», «Похожие» (`TvHorizontalRow`).
  - `TvSeasonTab` — шапка эпизода и `TvHorizontalRow` из `TvEpisode` с подгрузкой страниц.
- **Кнопки `TvShowActions`** — свой ряд `TvButton`+`TvIconButton` с обработчиками на публичных вызовах (§2).
  Скачать: нет загрузок — `queueDownloadWithFeedback`; всё скачано — он же с `onDelete`, как
  `action_buttons.dart:694`; частичные/пауза/ошибка/правило синхронизации — иконка состояния из
  `DownloadProvider`, OK открывает экран Загрузок Plezy (D3).
- **Навигация фокуса.** Явные `FocusNode` для вкладок, главной кнопки, последнего эпизода каждой вкладки;
  ↑/↓ между уровнями — обработчиками клавиш, как в S15/S16. «Назад» — `PopScope`: сезон → «Сериал»; иначе pop с
  `watchStateChanged`.
- **Обновление (H14, H15).** Экран подмешивает `WatchStateAware`/`DeletionAware` Plezy (или подписку на те же
  потоки, как S16) и правит кэш эпизодов; после плеера (`onRefresh`) и после действий — повторный
  `fetchItemWithOnDeck` и перезапрос загруженных страниц текущего сезона и списка сезонов (для бейджей).
  Флаг `watchStateChanged` ставится при любом событии просмотра.

## 4. Решения

- **D1 Точка подключения — mnh, не большие файлы.** Покрывает все пути через `navigateToMediaItemDetails`.
  «Перейти к сериалу» из `media_context_menu.dart` и `_navigateToSeries` в MDS вызывают `mediaDetailRoute`
  напрямую — не покрываются (H1, принятое ограничение). Отвергнуто: вынос `mediaDetailRoute` из MDS в
  отдельный файл — правка большого файла.
- **D2 Своя оркестрация.** Приватную загрузку Plezy не вызвать; копируем порядок и правила со ссылками на
  источник; проверка апстрим-мержа (`plezytv-upstream.yml`) предупреждает об изменениях
  `media_detail_screen.dart`, `action_buttons.dart`, `episode_collection.dart`, `plex_season_display.dart`,
  `media_navigation_helper.dart`, `media_context_menu.dart`, `download_utils.dart`
  (по образцу предупреждений S12/S16).
- **D3 Скачивание частично упрощено** (см. H7): новая загрузка и удаление — публичный `queueDownloadWithFeedback`;
  продолжение частичной загрузки и действия правил синхронизации приватны в Plezy — экран Загрузок.
- **D4 Офлайн — апстрим.** Другой источник данных (Загрузки) и урезанный набор; на TV редок.
- **D5 Отдельный сезон без сериала** — апстрим (H1).

## 5. Потоки

1. Вход: route → контроллер грузит сериал → шапка, вкладки; сезоны → вкладки и ряд сезонов; если задан
   `initialSeason*`/`initialEpisodeId` — выбрать вкладку (`preferredSeasonIndex`) и после загрузки
   страницы с эпизодом поставить на него фокус.
2. Сезон: OK по постеру → вкладка → загрузить первую страницу (и далее до первого непросмотренного) → фокус.
3. Плеер: OK по эпизоду → `navigateToVideoPlayerWithRefresh(onRefresh: controller.refresh)` → возврат →
   обновление → фокус на тот же или следующий непросмотренный (H14).

## 6. Согласование

Утверждено координатором 2026-10-24 по делегированию пользователя. Локальные детали в рамках §3 — разработке.
