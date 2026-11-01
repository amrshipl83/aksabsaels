// lib/services/shira_mic_consent.dart
//
// First-use gate for Shira Mic: the in-app microphone disclosure is shown
// once, only when the user actually starts voice recording — never at app
// open or login. Pure logic (unit-testable); the widget owns the dialog,
// the SharedPreferences read/write, and the OS permission request.
class ShiraMicConsent {
  /// SharedPreferences flag recording that the user accepted the disclosure.
  static const String prefsKey = 'shira_mic_disclosure_accepted_v1';

  /// Returns true when the disclosure must be shown before requesting the
  /// OS microphone permission (i.e. the user never accepted it before).
  /// Any other value (including first run `null`) means "show it".
  static bool shouldShowDisclosure(bool? accepted) => accepted != true;
}
