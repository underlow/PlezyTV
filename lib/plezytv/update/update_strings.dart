import 'package:flutter/widgets.dart';

/// Fork-owned translations; no generated upstream localization files change.
class UpdateStrings {
  UpdateStrings(BuildContext context) : ru = Localizations.localeOf(context).languageCode == 'ru';
  final bool ru;
  String get check => ru ? 'Проверить обновления' : 'Check for updates';
  String get install => ru ? 'Установить' : 'Install';
  String get later => ru ? 'Позже' : 'Later';
  String get skip => ru ? 'Пропустить эту версию' : 'Skip this version';
  String get cancel => ru ? 'Отмена' : 'Cancel';
  String get current => ru ? 'Текущая версия' : 'Current version';
  String get latest => ru ? 'Установлена последняя версия' : 'Up to date';
  String get failed => ru ? 'Не удалось обновить PlezyTV' : 'PlezyTV update failed';
  String get permission => ru
      ? 'Разрешите установку приложений для PlezyTV в открывшихся настройках. Вернитесь и нажмите «Установить» ещё раз.'
      : 'Allow installing apps for PlezyTV in the system settings. Return and press Install again.';
}
