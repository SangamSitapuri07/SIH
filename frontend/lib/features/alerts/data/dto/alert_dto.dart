import '../../../../core/utils/date_formatter.dart';
import '../../domain/entities/alert_item.dart';

/// DTO for `/api/v1/alerts`. Required alert body fields are rejected when the
/// provider response is malformed; optional provenance is left null.
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

  const AlertDto({required this.id, this.severity, required this.title, this.titleHi, required this.message, this.messageHi, this.source, this.issuedAt, this.expiresAt, this.affectedArea, this.isActive});

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true);
    return DateFormatter.parseIso(value);
  }

  factory AlertDto.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final title = json['title']?.toString();
    final message = json['message']?.toString();
    if (id == null || title == null || message == null) {
      throw const FormatException('Provider alert is missing an id, title, or message.');
    }
    return AlertDto(
      id: id,
      severity: json['severity']?.toString(),
      title: title,
      titleHi: json['title_hi']?.toString(),
      message: message,
      messageHi: json['message_hi']?.toString(),
      source: json['source']?.toString(),
      issuedAt: _parseTimestamp(json['issued_at']),
      expiresAt: _parseTimestamp(json['expires_at']),
      affectedArea: json['affected_area']?.toString(),
      isActive: json['is_active'] as bool?,
    );
  }

  AlertItem toEntity({bool isCached = false, bool isStale = false}) => AlertItem(
        id: id,
        severity: severity,
        title: title,
        titleHi: titleHi,
        message: message,
        messageHi: messageHi,
        source: source,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        affectedArea: affectedArea,
        isActive: isActive,
        isCached: isCached,
        isStale: isStale,
      );
}
