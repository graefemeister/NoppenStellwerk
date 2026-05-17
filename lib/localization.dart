import 'package:flutter/material.dart';

class L10n {
  static String lang = 'de';

  static const Map<String, Map<String, String>> _localizedValues = {
    'de': {
      'settings': 'Einstellungen',
      'lang_changed': 'Sprache geändert',
      'ui_auto_scale': 'Automatische Skalierung',
      'ui_auto_scale_desc': 'Passt die Benutzeroberfläche automatisch an die Bildschirmgröße an.',
      'ui_scaling_manual': 'Manuelle Skalierung',
      'display_always_on': 'Bildschirm immer an',
      'display_always_on_desc': 'Verhindert, dass das Display während des Betriebs ausgeht.',
      'design_theme': 'Design / Theme',
      'theme_system': 'System-Standard',
      'theme_light': 'Helles Design',
      'theme_dark': 'Dunkles Design',
    },
    'en': {
      'settings': 'Settings',
      'lang_changed': 'Language changed',
      'ui_auto_scale': 'Automatic Scaling',
      'ui_auto_scale_desc': 'Automatically adjusts the UI to your screen size.',
      'ui_scaling_manual': 'Manual Scaling',
      'display_always_on': 'Display Always On',
      'display_always_on_desc': 'Prevents the display from turning off during operation.',
      'design_theme': 'Design / Theme',
      'theme_system': 'System Default',
      'theme_light': 'Light Design',
      'theme_dark': 'Dark Design',
    },
  };

  static String getString(String key) {
    return _localizedValues[lang]?[key] ?? key;
  }
}

extension LanguageX on String {
  String get tr => L10n.getString(this);
}