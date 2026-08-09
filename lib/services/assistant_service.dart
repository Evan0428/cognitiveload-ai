import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'cognitive_load_engine.dart';
import 'rpm_service.dart';

/// Avatar assistant (Chua Yi Zhe) — turns the fused cognitive-load result into
/// a friendly rule-based coaching message and speaks it aloud (flutter_tts).
/// Delivers the intervention the report calls for (Objective 3), voiced by the
/// user's own avatar.
class AssistantService {
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;
  String? _appliedFor; // which voice profile is currently loaded

  /// The written/spoken coaching line for the current state.
  String messageFor(CognitiveLoadResult r, {String? name}) {
    final who = _name(name);
    switch (r.level) {
      case LoadLevel.overload:
        return "Hey$who, today's workload is too hard. Please stop and take a "
            "proper rest before you burn out.";
      case LoadLevel.high:
        if (r.readinessScore < 45) {
          return "Your load is heavy$who and your body shows low recovery. "
              "Take a real break now.";
        }
        return "Your load is heavy right now$who. A short recovery break will "
            "keep you sharp.";
      case LoadLevel.elevated:
        return "A manageable day$who. Pace yourself and take small breaks "
            "between tasks.";
      case LoadLevel.safe:
        if (r.readinessScore < 45) {
          return "Your schedule is light$who, but your recovery is low. "
              "Prioritise rest today.";
        }
        return "You're well balanced$who. Your workload is under control — a "
            "great time to focus.";
    }
  }

  /// Spoken when the day's heavy work has just cleared.
  String workloadOverMessage({String? name}) =>
      "Great job${_name(name)}! Your heavy workload is over for now. "
      "Time to relax and recover.";

  /// Speak in the voice of the currently selected character — each assistant
  /// has its own pitch/rate (and a preferred system voice where available), so
  /// the robot sounds different from the human coaches.
  Future<void> speak(String text) async {
    try {
      final v = RpmService.currentVoice;

      // Re-apply whenever the user switches character.
      if (!_configured || _appliedFor != v.toString()) {
        await _tts.setLanguage(v.locale);
        await _tts.setSpeechRate(v.rate);
        await _tts.setPitch(v.pitch);
        if (v.voice != null) {
          try {
            await _tts.setVoice({'name': v.voice!, 'locale': v.locale});
          } catch (_) {
            // Voice not installed on this device — pitch/rate still differ.
          }
        }
        _configured = true;
        _appliedFor = v.toString();
      }

      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  String _name(String? name) =>
      (name != null && name.trim().isNotEmpty && name != '...')
          ? ' ${name.trim().split(' ').first}'
          : '';
}
