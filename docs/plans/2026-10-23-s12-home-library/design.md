# S12 — Оболочка TV-интерфейса: дизайн

Контракт поведения — [requirements.md](requirements.md). Сведения о коде — из чтения репозитория 2026-10-23.

## 1. Обзор

`TvShell` перестаёт оборачивать `MainScreen` и сам становится домом профиля на TV: своё меню (`TvSideMenu`),
стопка апстримных экранов разделов и повторённая обвязка `MainScreen`. Другого пути без правки больших файлов нет:
логика `MainScreen` приватна, его меню и экраны создаются внутри. Вариант «`MainScreen` невидимым двигателем под
своим меню» отвергнут: апстримное меню остаётся в дереве и забирает фокус.

Цена — исправления Plezy в `MainScreen` не доходят до TV сами; компенсируется перечнем повторённых обязанностей в
`docs/plezytv/tv-ui.md` и пометкой в еженедельном PR мержа апстрима (D9).

## 2. Существующая система

- Вход: `ProfileSessionNavigator._onGenerateRoute` (`lib/navigation/profile_session_screen.dart`) →
  `TvUi.profileHome` (`lib/plezytv/tv_ui/tv_ui.dart`) → `TvShell`. Провайдеры сессии (`MultiServerProvider`,
  `LibrariesProvider`, `HiddenLibrariesProvider`, `OfflineModeProvider`, `ActiveProfileProvider/Binder`,
  `DiscoverProvider`, `DownloadProvider`, `CompanionRemoteProvider`, `MiniPlayerInsetController` и др.) создаются
  там же и переживают замену.
- `lib/screens/main_screen.dart` (не правим): разделы через `IndexedStack` с ленивым монтированием, `GlobalKey`
  экранов и возможности из `lib/mixins/refreshable.dart` и `tab_visibility_aware.dart`; приватные обязанности —
  запуск онлайн-служб, офлайн, выбор профиля, смена профиля, обновление после сна, ссылки лаунчера, Watch Together,
  пульт-компаньон, «Назад»/выход, проверка обновлений. Публичные помощники там же: `runInitialProfilePrompt`,
  `ContentRefreshResumeGate`, `ProfileSelectionResumeGate`, `shouldShowProfileSelectionOnResume`.
- Отдельные файлы для переиспользования: `navigation/navigation_tabs.dart` (видимость разделов, стартовый),
  `navigation/main_screen_scope.dart` (`MainScreenFocusScope`), `screens/libraries/library_quick_picker_sheet.dart`,
  `services/system_shelf_service.dart`, `LiveTvDeepLink`, `CompanionRemoteReceiver`, `UpdateService`,
  `AppExitService`, `widgets/auth_error_banner.dart`, `profileInvalidationAction`,
  `shouldRetryActiveProfileBindAfterReconnect`.
- S5: `lib/plezytv/screen_links/screen_link_router.dart` ждёт `CompanionRemoteReceiver.navigationOwner` и колбэков
  `onHome`/`onTabSettings`, ищет `MainScreenFocusScope` в дереве для `selectLibrary`; от него же стартует
  `PlezyTvUpdater`.
- S6: `TvSideMenu`, `TvButton`, `TvTheme`, токены — `lib/plezytv/tv_ui/`.
- Настройки: `lib/screens/settings/settings_screen.dart` уже содержит точку S5 (`PlezyTvUpdater.settingsTile`).

## 3. Архитектура

Новый код — `lib/plezytv/tv_ui/shell/`; `TvShell` остаётся точкой входа `TvUi.profileHome`.

- **Контроллер сессии оболочки** (без UI, живёт столько же, сколько `TvShell`). Повторяет обязанности `MainScreen`:
  - запуск онлайн-служб после устоявшейся привязки профиля (с тем же запасным таймаутом), докачка загрузок при
    каждом новом сервере онлайн (P1);
  - выбор профиля при старте и при поздно пришедших профилях через `runInitialProfilePrompt`, с учётом
    `initialPromptHandled` (S2);
  - смена профиля / пересвязка → сброс кэша, библиотек и полное обновление разделов (P4);
  - обновление после сна через `ContentRefreshResumeGate`, Seerr при возврате, выбор профиля при возврате — только
    где Plezy его делает (на TV — нет) (P4);
  - ссылки лаунчера и Live TV через `SystemShelfService`, Watch Together `navigatorOpener` (P2);
  - автозапуск сервера пульта-компаньона по настройке, проверка обновлений Plezy по `autoCheckUpdatesOnStartup` (P3, P5);
  - офлайн: слушает `OfflineModeProvider`, повтор подключения (D7).
  Сообщает виджету только своё наблюдаемое состояние (онлайн/офлайн, идёт ли повтор) и принимает команды.
- **Виджет `TvShell`**: `TvTheme`, меню, область раздела, `MainScreenFocusScope`, «Назад», экран «Нет связи»,
  колбэки пульта-компаньона.

Решения:

- **D1. Разделение контроллер / виджет** — обязанности тестируются без экрана, виджет тонкий.
- **D2. Разделы — апстримные экраны** (`DiscoverScreen`, `LibrariesScreen`, `LiveTvScreen`, `ExploreScreen`,
  `SearchScreen`, `DownloadsScreen`, `SettingsScreen`) с теми же параметрами и своими `GlobalKey`; `IndexedStack`,
  ленивое монтирование, `TickerMode` для скрытых; при переключении — `TabVisibilityAware.onTabHidden/onTabShown`,
  `FocusableTab.focusActiveTabIfReady`, обновление Главной при показе, как в Plezy (F5, P4). Апстримные экраны
  получают только то, что им даёт `MainScreen`; их вид не меняем.
- **D3. `MainScreenFocusScope` от оболочки:** `focusSidebar` → раскрыть меню на текущем пункте (F1, F4);
  `selectLibrary(globalKey)` → раздел библиотек + `LibraryLoadable.loadLibraryByKey` (M6, S5); `openSettings` →
  Настройки; ширина/левая граница контента — ширина свёрнутого меню, постоянная (меню раскрывается поверх, M3).
- **D4. Пульт-компаньон:** оболочка ставит `navigationOwner` и колбэки `onHome`, `onTabNext/Previous`,
  `onTabDiscover/Libraries/Search/Downloads/Settings`, `onSearchAction`, снимает их при уничтожении. `onTabLibraries`
  открывает первую видимую библиотеку. S5 работает без изменений `screen_link_router`.
- **D5. Меню:** `TvSideMenu` (S6), дополнить прокруткой за фокусом (M3). Пункты (M1) собираются из
  `LibrariesProvider` минус `HiddenLibrariesProvider`, `MultiServerProvider.hasLiveTv`, источников каталога и
  настройки Explore, состояния музыкального плеера (как определяет Plezy пункт «Сейчас играет»), N1 и офлайна;
  пересборка по изменениям этих источников (M2). Имя сервера — при неуникальном названии. «Ещё» (M5) открывает
  `LibraryQuickPickerSheet` (группировка по серверам, со скрытыми). «Сейчас играет» открывает то же, что в Plezy.
- **D6. «Назад»:** обработчик на области меню: открытое меню → корень (Главная или «Нет связи»); на корне — подсказка
  и выход вторым нажатием в течение 3 с через `AppExitService.requestExit` (F3). Обработчик на области раздела
  ловит «Назад», не обработанный контентом, и раскрывает меню (F4). → в меню — закрыть и вернуть фокус (F2).
- **D7. Офлайн:** офлайн = `OfflineModeProvider.isOffline` или старт без подключения до первого сервера (как
  `_offlineUntilConnected`). Экран «Нет связи» — свой виджет на `TvButton`, без строки о синхронизации (у Plezy нет
  времени последней успешной связи с сервером). «Повторить» повторяет `_triggerReconnect`: `binder.start`, проверка
  здоровья, `reconnectOfflineServers(forceRediscovery)`, `rebindActive` по
  `shouldRetryActiveProfileBindAfterReconnect`; неуспех — сообщение «не удалось подключиться». «Настройки
  подключений» — раздел Настройки. O4: при потере связи раздел не меняется, меняются меню и корень; если
  текущего раздела больше нет в меню, у меню нет текущего пункта до ухода. O3: при возврате связи — раздел,
  открытый до потери, иначе стартовый.
- **D8. N1:** свой ключ настройки PlezyTV (по умолчанию выкл), переключатель на TV в `SettingsScreen` рядом с
  существующей точкой S5; меню слушает ключ.
- **D9. Сверка с апстримом:** `tv-ui.md` перечисляет повторённые обязанности со ссылкой на их место в
  `main_screen.dart`; workflow еженедельного мержа помечает в PR изменение `lib/screens/main_screen.dart` и
  `navigation_tabs.dart`, `main_screen_scope.dart`.

## 4. Состояние

| Значение | Владелец | Читатели | Жизнь и переходы |
|---|---|---|---|
| Текущий раздел (вкладка или библиотека) | виджет `TvShell` | меню, стопка, пульт | старт по S1; меняется выбором, ссылкой, пультом, F3; восстанавливается при O3 |
| Раздел до потери связи | `TvShell` | O3 | запоминается при переходе в офлайн, сбрасывается после восстановления |
| Смонтированные разделы и их `GlobalKey` | `TvShell` | контроллер (обновления) | на всю жизнь оболочки; сброс экранов при смене профиля |
| Меню раскрыто, откуда пришёл фокус | `TvShell`/`TvSideMenu` | F2 | на время фокуса в меню |
| Время первого «Назад» на корне | `TvShell` | F3 | сбрасывается сменой раздела и через 3 с |
| Онлайн/офлайн, идёт повтор | контроллер | `TvShell` | по `OfflineModeProvider` и повтору; повтор не запускается дважды |
| Службы запущены, покрытые серверы докачки, профиль-показан | контроллер | — | как в `MainScreen`; разовые флаги на жизнь оболочки |

Асинхронные шаги проверяют, что оболочка ещё жива; запоздавший результат повтора после ухода игнорируется.

## 5. Контракты

- `MainScreenFocusScope` — тот же тип и смысл полей, что даёт `MainScreen` (D3).
- `CompanionRemoteReceiver` — те же колбэки и `navigationOwner` (D4); при уничтожении — обнуление, если владелец всё
  ещё оболочка.
- `TvUi.profileHome` и `TvShell(isOfflineMode, initialPromptHandled)` — без изменений.
- Ключ N1 — новый, в хранилище настроек Plezy; отсутствие ключа = выкл.

## 6. Риски

- Пропуск обязанности `MainScreen` — смягчение: перечень P1–P5 в тестах контроллера и проверка на TV.
- Апстримные экраны могут предполагать раскладку `MainScreen` (боковой отступ, `SideNavigationBleedBuilder`) — вид
  допускается кривым, фокус и ← обязаны работать; проверяется на TV.
- `MiniPlayerInsetController`: на TV `MainScreen` отступы не сообщает; оболочка тоже не сообщает, но приостанавливает
  при уходе на другой экран, как `MainScreen` (P5).

## 7. Примеры приёмки

| Начало | Действие | Ожидаемо | R |
|---|---|---|---|
| Сервер на связи, стартовая — Главная | запуск | Главная Plezy, фокус в контенте, меню свёрнуто | S1 |
| Фокус в первой колонке Главной | ← | меню раскрыто на «Главная» | F1 |
| Меню раскрыто, фокус пришёл из ряда | → | меню свёрнуто, фокус на том же элементе | F2 |
| Открыты «Фильмы», меню раскрыто | Назад | Главная | F3 |
| Главная, меню раскрыто | Назад, Назад за 3 с | подсказка, выход | F3 |
| Вкладки библиотеки в фокусе | Назад | меню раскрыто | F4 |
| Две скрытые библиотеки | «Ещё» → скрытая | открыта скрытая библиотека, нет текущего пункта | M5, M6 |
| Сервер выключен при старте | запуск | «Нет связи», «Повторить» в фокусе; меню: Настройки | O1, O2 |
| «Нет связи», сервер поднят | «Повторить» | «Подключение…», затем полное меню и стартовый раздел | O1, O3 |
| Открыты «Сериалы», связь пропала | — | «Сериалы» на экране, меню сокращено, Назад из меню → «Нет связи» | O4 |
| Онлайн | `plezytv://screen/library?...` по adb | открыта библиотека | P3 |
| Канал лаунчера | выбор эпизода | воспроизведение | P2 |
| Включена N1 | открыть меню | есть «Загрузки» | N1 |
| Не TV | запуск | апстримный `MainScreen` | Совместимость |

## 8. Согласование

Подход и D1–D9 согласованы пользователем 2026-10-23 («давай пиши все»); детали состояния и контракты делегированы
координатору, независимая проверка — Codex.
