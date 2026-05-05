enum TextSystemSaveStatus {
  clean,
  dirty,
  saving,
  saved,
  failed,
}

/// User-facing persistence state for a text-system document.
///
/// This object is deliberately UI-neutral so tiny text fields, notes, and the
/// future premium writer can all expose the same save confidence indicators.
class TextSystemSaveState {
  const TextSystemSaveState({
    required this.status,
    this.lastSavedAt,
    this.lastAttemptedAt,
    this.message,
    this.error,
  });

  const TextSystemSaveState.clean()
      : status = TextSystemSaveStatus.clean,
        lastSavedAt = null,
        lastAttemptedAt = null,
        message = null,
        error = null;

  final TextSystemSaveStatus status;
  final DateTime? lastSavedAt;
  final DateTime? lastAttemptedAt;
  final String? message;
  final Object? error;

  bool get hasUnsavedChanges => status == TextSystemSaveStatus.dirty;
  bool get isSaving => status == TextSystemSaveStatus.saving;
  bool get isFailed => status == TextSystemSaveStatus.failed;

  TextSystemSaveState copyWith({
    TextSystemSaveStatus? status,
    DateTime? lastSavedAt,
    DateTime? lastAttemptedAt,
    String? message,
    Object? error,
    bool clearError = false,
  }) {
    return TextSystemSaveState(
      status: status ?? this.status,
      lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      lastAttemptedAt: lastAttemptedAt ?? this.lastAttemptedAt,
      message: message ?? this.message,
      error: clearError ? null : error ?? this.error,
    );
  }
}
