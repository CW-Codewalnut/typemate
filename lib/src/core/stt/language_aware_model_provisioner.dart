import 'stt_model_provisioner.dart';

/// Desktop model provisioning: one [SttModelProvisioner] per downloadable
/// model, surfaced to the UI as the single provisioner for whichever model
/// the selected language needs. Languages whose model is bundled with the
/// install have no entry and report ready with nothing to download.
///
/// Several language codes may share one provisioner (all 25 Parakeet
/// languages share the Parakeet model), so listeners are attached to the
/// distinct set, not per code.
class LanguageAwareModelProvisioner extends SpeechModelProvisioner {
  LanguageAwareModelProvisioner({
    required Map<String, SttModelProvisioner> provisionersByLanguageCode,
    required this.languageCodeProvider,
  }) : _byLanguageCode = provisionersByLanguageCode {
    for (final provisioner in _distinctProvisioners) {
      provisioner.addListener(notifyListeners);
    }
  }

  final Map<String, SttModelProvisioner> _byLanguageCode;
  final String Function() languageCodeProvider;

  Set<SttModelProvisioner> get _distinctProvisioners => {
    ..._byLanguageCode.values,
  };

  /// The provisioner for the selected language, or null when that
  /// language's model ships with the install.
  SttModelProvisioner? get active =>
      _byLanguageCode[languageCodeProvider().trim().toLowerCase()];

  @override
  SttModelProvisionPhase get phase =>
      active?.phase ?? SttModelProvisionPhase.ready;

  @override
  double get progress => active?.progress ?? 1;

  @override
  String? get errorMessage => active?.errorMessage;

  @override
  bool get isReady => active?.isReady ?? true;

  @override
  int get expectedTotalBytes => active?.expectedTotalBytes ?? 0;

  /// Re-checks the selected language's model. Notifies first: a language
  /// change swaps which provisioner is active, and the UI must re-render
  /// even when the new language needs no provisioning at all.
  @override
  Future<void> refresh() async {
    final current = active;
    notifyListeners();
    await current?.refresh();
  }

  @override
  Future<void> download() async {
    await active?.download();
  }

  @override
  void dispose() {
    for (final provisioner in _distinctProvisioners) {
      provisioner.removeListener(notifyListeners);
      provisioner.dispose();
    }
    super.dispose();
  }
}
