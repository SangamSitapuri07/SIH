import '../../../../core/utils/date_formatter.dart';
import '../../domain/entities/alert_item.dart';

/// DTO for /api/v1/alerts response.
class AlertDto {
  final String id;
  final String? severity;
  final String title;
  final String? titleHi;
  final String message;
  final String? messageHi;
  final String? source;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final String? affectedArea;
  final bool? isActive;

  AlertDto({
    required this.id,
    this.severity,
    required this.title,
    this.titleHi,
    required this.message,
    this.messageHi,
    this.source,
    this.issuedAt,
    this.expiresAt,
    this.affectedArea,
    this.isActive,
  });

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true);
    }
    return DateFormatter.parseIso(value);
  }

  factory AlertDto.fromJson(Map<String, dynamic> json) {
    return AlertDto(
      id: json['id'] as String? ?? 'alt_${DateTime.now().millisecondsSinceEpoch}',
      severity: json['severity'] as String? ?? 'caution',
      title: json['title'] as String? ?? 'Marine Weather Alert',
      titleHi: json['title_hi'] as String?,
      message: json['message'] as String? ?? 'Caution advised in maritime operations.',
      messageHi: json['message_hi'] as String?,
      source: json['source'] as String? ?? 'INCOIS / IMD',
      issuedAt: _parseTimestamp(json['issued_at']),
      expiresAt: _parseTimestamp(json['expires_at']),
      affectedArea: json['affected_area'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  AlertItem toEntity() {
    return AlertItem(
      id: id,
      severity: severity ?? 'caution',
      title: title,
      titleHi: titleHi,
      message: message,
      messageHi: messageHi,
      source: source ?? 'INCOIS / IMD',
      issuedAt: issuedAt ?? DateTime.now(),
      expiresAt: expiresAt,
      affectedArea: affectedArea,
      isActive: isActive ?? true,
    );
  }
}
