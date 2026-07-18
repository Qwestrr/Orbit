import 'package:flutter/material.dart';

class CustomQuickNotificationTemplate {
  static const String _defaultIconKey = 'chat';
  static const Map<String, IconData> _iconsByKey = <String, IconData>{
    'schedule': Icons.schedule,
    'chat': Icons.chat_bubble_outline,
    'shield': Icons.shield_outlined,
    'priority': Icons.priority_high,
    'location': Icons.location_searching,
    'airTraffic': Icons.flight_takeoff,
    'alert': Icons.notifications_active_outlined,
  };

  final String id;
  final String label;
  final String messageTemplate;
  final String iconKey;
  final int accentColorArgb;
  final bool isExplicit;

  const CustomQuickNotificationTemplate({
    required this.id,
    required this.label,
    required this.messageTemplate,
    required this.iconKey,
    required this.accentColorArgb,
    required this.isExplicit,
  });

  IconData get icon => _iconsByKey[iconKey] ?? _iconsByKey[_defaultIconKey]!;

  Color get accentColor => Color(accentColorArgb);

  static String keyForIcon(IconData icon) {
    for (final entry in _iconsByKey.entries) {
      if (entry.value == icon) {
        return entry.key;
      }
    }
    return _defaultIconKey;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'messageTemplate': messageTemplate,
      'iconKey': iconKey,
      'accentColorArgb': accentColorArgb,
      'isExplicit': isExplicit,
    };
  }

  factory CustomQuickNotificationTemplate.fromJson(Map<String, dynamic> json) {
    return CustomQuickNotificationTemplate(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      messageTemplate: json['messageTemplate'] as String? ?? '',
      iconKey: json['iconKey'] as String? ?? _legacyIconKeyFromJson(json),
      accentColorArgb:
          json['accentColorArgb'] as int? ?? Colors.blue.toARGB32(),
      isExplicit: json['isExplicit'] as bool? ?? false,
    );
  }

  static String _legacyIconKeyFromJson(Map<String, dynamic> json) {
    final fontFamily = json['iconFontFamily'] as String?;
    final fontPackage = json['iconFontPackage'] as String?;
    final codePoint = json['iconCodePoint'] as int?;

    if (fontPackage != null ||
        (fontFamily != null && fontFamily != 'MaterialIcons') ||
        codePoint == null) {
      return _defaultIconKey;
    }

    switch (codePoint) {
      case 0xe57f:
        return 'schedule';
      case 0xe0ca:
        return 'chat';
      case 0xe574:
        return 'shield';
      case 0xe645:
        return 'priority';
      case 0xe1b7:
        return 'location';
      case 0xe904:
        return 'airTraffic';
      case 0xe7f7:
        return 'alert';
      default:
        return _defaultIconKey;
    }
  }
}
