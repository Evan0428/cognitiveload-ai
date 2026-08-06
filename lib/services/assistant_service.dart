import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'cognitive_load_engine.dart';

/// Avatar assistant (Chua Yi Zhe) — turns the fused cognitive-load result into
/// a friendly rule-based coaching message and speaks it aloud (flutter_tts).
/// Delivers the intervention the report calls for (Objective 3), voiced by the
/// user's own avatar.
class AssistantService {
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;

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

  Future<void> speak(String text) async {
    try {
      if (!_configured) {
        await _tts.setLanguage('en-US');
        await _tts.setSpeechRate(0.48); // calmer, clearer pace
        await _tts.setPitch(1.05);
        _configured = true;
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
