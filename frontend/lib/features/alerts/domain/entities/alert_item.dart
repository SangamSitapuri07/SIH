/// A verified provider alert. Optional metadata remains unavailable when the
/// source did not publish it; the UI must not manufacture a time or agency.
class AlertItem {
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
  final bool isCached;
  final bool isStale;

  const AlertItem({
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
    this.isCached = false,
    this.isStale = false,
  });
}
