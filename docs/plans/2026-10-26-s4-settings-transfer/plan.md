# S4 — План: экспорт и импорт настроек на TV и через adb

Контракт — [`requirements.md`](requirements.md) (R1–R7, A1–A7). Правила форка — `docs/projects/plezy-tv/project.md`
(«Контекст и ограничения»): апстримные файлы в тысячи строк не правим, свой код — в `lib/plezytv/`, правки апстрима —
маленькие точки подключения; правила TV-интерфейса — `docs/plezytv/tv-ui.md`.

## 1. Результат

PlezyTV на TV умеет экспортировать и импортировать настройки в один файл
`/sdcard/Android/data/com.underlow.plezytv/files/plezytv-settings.json` — из настроек пультом и ссылками
`plezytv://settings/export|import` через adb. Скилл `tv` (репозиторий things) сохраняет этот файл в снимок и раскатывает
его на телек.

## 2. Технический подход

Опирается на код Plezy, проверенный при планировании:

- `SettingsExportService` (`lib/services/settings_export_service.dart`) уже имеет публичные чистые функции
  `buildExportMap(prefs, currentUserUuid:, appVersion:)` и `applyImportMap(data, prefs, currentUserUuid:)`. Формат:
  `{formatVersion: 1, appVersion, exportedAt, platform, prefs: {key: {type, value}}}`. `applyImportMap` пропускает
  неизвестные ключи (`_policyFor == null` → `skipped`), проверяет `formatVersion` и бросает
  `InvalidExportFileException`. Активный пользователь — `StorageService.activeUserScope()`; без него Plezy бросает
  `NoUserSignedInException`.
- Настройки PlezyTV — `TvSettings.showDownloads` (`plezytv_show_downloads`, bool) и `TvSettings.searchKeyboardLayout`
  (`plezytv_search_keyboard_layout`, string) в `lib/plezytv/tv_ui/tv_settings.dart`; их нет в
  `SettingsService.portablePrefs`. `settings_service.dart` — 1756 строк, его не правим.
- Применение после импорта в Plezy — `_handleImportSettings` в `settings_screen.dart` (~строки 885–925):
  `SettingsMutationService.captureRootConfiguration()` до записи, затем `SettingsService.refreshListenables()`,
  `HiddenLibrariesProvider.refresh()`, `LibrariesProvider.refresh()`,
  `SettingsMutationService().applyStoredEffects(context, previousRootConfiguration:)`.
- Раздел «Резервная копия» в `settings_screen.dart` (1040 строк) скрыт на TV условием на строке ~245; там же уже есть
  хук S12 `?TvSettings.settingsTile(context)` (строка ~240).
- Ссылки S5: `ScreenLink` (`lib/plezytv/screen_links/screen_link.dart`) принимает только host `screen`; очередь
  `ScreenLinkQueue` ждёт готовности профиля; `ScreenLinkRouter` держит таблицу обработчиков по `ScreenTarget` и даёт
  `_context`. Ссылки приходят через `SystemShelfService` (`ScreenLinkRouter.instance.claim`). В
  `AndroidManifest.xml` для `plezytv` объявлены host `play`, `live`, `screen`.

Решения:

1. **Свой сервис переноса** в `lib/plezytv/` (например, `settings_transfer/`). Экспорт: карта Plezy из
   `buildExportMap` + записи PlezyTV в том же `prefs` в том же формате `{type, value}`; запись в
   `getExternalStorageDirectory()` (path_provider, внешняя папка приложения, разрешения не нужны) под фиксированным
   именем, с перезаписью. Импорт: прочитать файл, `applyImportMap` для ключей Plezy (свои ключи он пропустит),
   затем свои ключи PlezyTV с проверкой типа; невалидные свои — пропуск. Файла нет / не JSON / не объект / не тот
   `formatVersion` — понятная ошибка до любой записи. Число ключей в результате — общее (Plezy + PlezyTV).
   Применение (R5) — те же шаги, что `_handleImportSettings`, в одной функции сервиса, которую зовут и TV-раздел, и
   ссылка. `SettingsExportService` и `settings_service.dart` не меняем.
2. **TV-раздел.** На TV вместо скрытого раздела Plezy показывается свой раздел «Резервная копия» (две плитки:
   экспорт с путём к файлу в сообщении; импорт с подтверждением, как у Plezy) через точку подключения рядом с
   существующим хуком `TvSettings` в `settings_screen.dart` — правка апстрима в пару строк. Строки — в
   `TvStrings` (как остальные строки PlezyTV). На телефоне и десктопе раздел Plezy как был (R7).
3. **Ссылки.** `plezytv://settings/export` и `plezytv://settings/import` проходят через ту же `ScreenLinkQueue` (ждут
   профиль, новая ссылка заменяет ожидающую — как у S5): `ScreenLink` признаёт host `settings` с путями `export` /
   `import` без параметров, у роутера — два новых обработчика. Импорт по ссылке — без подтверждения. Итог — строка в
   лог `PlezyTV` (успех с числом ключей или причина) и короткое уведомление на экране. В манифест — фильтр для host
   `settings` **без** категории `BROWSABLE`: `adb shell am start -d` работает, а ссылка со страницы в браузере — нет.
   Записанный риск: на Android 9 другое приложение с доступом к памяти может подложить файл и прислать intent;
   переносятся только настройки без учётных данных — принимаем.
4. **Скилл `tv`.** `snapshot.sh` после основного снимка, если установлен `com.underlow.plezytv`: ссылка экспорта,
   ожидание появления свежего файла (ограниченное по времени), `adb pull` в папку снимка; не получилось — строка
   предупреждения, снимок не падает. Новый скрипт раскатки `<ip:port> <файл>`: push в путь R2 и ссылка импорта, затем
   показать строки лога `PlezyTV` о результате. `SKILL.md`: описание файла снимка и раскатки, раскатка — только после
   явного «да» (правило 1 скилла). `.gitignore` things не должен исключать `plezytv-settings.json`.

## 3. Задачи

### T1. Сервис переноса и раздел на TV

Вход: `requirements.md`, §2 (решения 1–2). Результат: R1, R2, R3, R5 в приложении.

- Сервис экспорта/импорта по решению 1; функция применения по образцу `_handleImportSettings`.
- Раздел «Резервная копия» на TV по решению 2.
- Сохранить: экспорт/импорт Plezy на телефоне и десктопе, существующие тесты `test/screens/settings/`.
- Тесты (`test/plezytv/`): экспорт содержит ключи PlezyTV и не содержит ни одного ключа вне переносимых (подложить в
  prefs токен/адрес сервера/ключ истории и проверить, что их нет); экспорт → импорт на чистые prefs восстанавливает и
  Plezy-, и PlezyTV-ключи, в т. ч. пользовательские под другим uuid; файл без ключей PlezyTV (как у Plezy)
  импортируется; файла нет / битый JSON / `formatVersion` больше поддерживаемого / нет пользователя — ошибка и prefs
  не изменились; повторный экспорт перезаписывает файл; на TV виден свой раздел, а не раздел Plezy, вне TV — раздел
  Plezy.
- Проверки: `flutter analyze`, `flutter test` целиком (известные 2 датозависимых теста Live TV падают и на базе —
  сверить с базой).

### T2. Ссылки adb и документация

Вход: T1 (сервис и функция применения). Результат: R4, R7, документация.

- Ссылки и манифест по решению 3; обработчики зовут сервис T1 и функцию применения.
- `docs/plezytv/dev-tools.md`: команды экспорта, `adb pull`/`adb push` с путём R2, импорта, чтение результата из
  `adb logcat -s PlezyTV`.
- Сохранить: все ссылки `plezytv://screen/...` и их тесты, `play`, `live`.
- Тесты: разбор `settings/export|import`, отказ для неизвестного пути и для параметров; ссылка импорта, пришедшая до
  готовности профиля, выполняется после неё (по образцу `screen_link_router_test.dart`); ошибка импорта по ссылке
  пишет причину и не меняет prefs; ссылки `screen/...` разбираются как раньше.
- Проверки: `flutter analyze`, `flutter test` целиком; сборка APK (`.tools/`) проходит, в собранном манифесте фильтр
  `settings` без `BROWSABLE`.

### T3. Скилл `tv` (репозиторий things)

Вход: R2 (путь), R4 (ссылки), решение 4. Не зависит от кода T1/T2, только от контракта.
Checkout: `~/Projects/things`, ветка `main`; там есть чужое изменение
(`.claude/skills/libra-visibility/state.db`) — не трогать, коммитить только файлы скилла `tv` явными путями.

- `snapshot.sh`, новый скрипт раскатки, `SKILL.md` по решению 4.
- Сохранить: остальной снимок без изменений, `--no-data`, правило «по умолчанию только чтение» (снимок только
  читает; ссылка экспорта пишет лишь файл в папке приложения).
- Проверки: `bash -n` обоих скриптов; `shellcheck`, если установлен; снимок без телека с PlezyTV не падает
  (ветка «не установлен»).

### После задач (координатор)

- Ревью изменения.
- Приёмка A1–A7 на телеке через adb, если телеки доступны (`devices.md` скилла `tv`); заодно проверить открытый
  вопрос R2 про `adb push` на Android 9 и 11. Что не удалось прогнать — записать в итог как непроверенное.
- Итог в этот план, статус S4 в проекте.

## 4. Пересмотр после приёмки на Xiaomi (2026-10-26)

Готово и остаётся в силе: T1 (`f4613af31`), T2 (`6081e3a33`), исправления `60be5e1dd`; things `a9c9702`, `f5205ac`,
`738f3cf`. Приёмка на Xiaomi (Android 11): ссылка экспорта пишет файл (`Settings export: 11 keys, …`), но adb не может
ни читать, ни писать `/sdcard/Android/data/com.underlow.plezytv/files/` (`Permission denied`). Требования R2, R4, R6,
A1, A2, A8 пересмотрены: канал adb — провайдер. Файл и его путь внутри приложения
(`getExternalStorageDirectory()` в Dart = `Context.getExternalFilesDir(null)` в Android) не меняются.

Решение 5. **Провайдер файла настроек.** Свой Kotlin `ContentProvider` рядом с кодом форка
(`android/app/src/main/kotlin/com/edde746/plezy/plezytv/`), authority `${applicationId}.settings`, `exported="true"`,
без `grantUriPermissions`. Один путь `settings.json` → `getExternalFilesDir(null)/plezytv-settings.json`. `openFile`
с режимом `r` — чтение (файла нет → `FileNotFoundException`), `w`/`wt` — запись с усечением; другие режимы, пути и
все `query/insert/update/delete` — отказ. Вызов не от uid shell (2000) или root (0) — `SecurityException` до любого
доступа к файлу. Образец провайдера в коде — `watchnext/SystemShelfArtworkProvider.kt`.

### T4. Провайдер и документация

Вход: решение 5, R2, R4, A8. Checkout: `/Users/underlow/Projects/PlezyTV`, ветка `flow/s4-settings-transfer`.

- Провайдер и запись в манифесте; `docs/plezytv/dev-tools.md` — команды `content read`/`content write` вместо
  `adb pull`/`adb push` и путь файла только как справка.
- Сохранить: Dart-сервис T1, ссылки T2, раздел на TV.
- Тесты (Robolectric, по образцу `android/app/src/test/kotlin/com/edde746/plezy/`): чтение и запись от shell-uid
  работают и попадают в тот же файл, что пишет Dart; чужой uid — отказ и на чтение, и на запись, файл не изменён;
  неизвестный путь и режим — отказ; чтение отсутствующего файла — `FileNotFoundException`.
- Проверки: `flutter analyze`, полный `flutter test`, Android unit-тесты, сборка APK; в собранном манифесте провайдер
  с authority `com.underlow.plezytv.settings`.

### T5. Скрипты скилла `tv` на провайдере

Вход: решение 5, R6. Не зависит от кода T4, только от контракта. Checkout: `~/Projects/things`, `main`, только
`.claude/skills/tv/` (чужой `libra-visibility/state.db` не трогать).

- `snapshot.sh`: свежесть экспорта — по строке `Settings export: …` в логе `PlezyTV` после ссылки (каталог приложения
  adb не читает, `stat` недоступен), затем `content read` в папку снимка; неудача — предупреждение, снимок не падает.
- `deploy-settings.sh`: `content write` вместо push; если на устройстве нет `content write` (Android 9) — `adb push`
  в путь приложения как запасной вариант; дальше как сейчас (ссылка импорта, ожидание итоговой строки).
- `SKILL.md` и мок-тест `test-settings-scripts.py` под новый канал, включая запасной вариант и сбой `content read`.
- Проверки: `bash -n`, мок-тест.

### После T4, T5

Ревью изменений T4/T5; повторная приёмка на Xiaomi: A1, A2, A3, A4, A5, A7 (на одном телеке), A6 — если есть файл с
телефона.
