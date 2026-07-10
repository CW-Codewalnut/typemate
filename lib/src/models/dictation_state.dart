enum DictationPhase {
  idle,
  preparing,
  listening,
  transcribing,
  inserting,
  error,
}

extension DictationPhaseLabel on DictationPhase {
  String get label {
    return switch (this) {
      DictationPhase.idle => 'Idle',
      DictationPhase.preparing => 'Preparing',
      DictationPhase.listening => 'Listening',
      DictationPhase.transcribing => 'Transcribing',
      DictationPhase.inserting => 'Inserting',
      DictationPhase.error => 'Needs attention',
    };
  }
}
