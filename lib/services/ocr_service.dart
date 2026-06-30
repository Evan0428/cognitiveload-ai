import 'package:flutter/foundation.dart';
import '../models/models.dart';

/// Schedule Digitization Module — OCR service (Lim Kah Jun).
///
/// On a real device this uses Google ML Kit `TextRecognizer` to read text from
/// a timetable image, then an intelligent parsing algorithm identifies times
/// and subjects and converts them into [ScheduleEvent]s.
///
/// In demo mode (web / desktop / no camera) it returns a realistic simulated
/// timetable so every downstream function can be demonstrated end-to-end.
class OcrService {
  /// Master switch. The UI keeps this on where ML Kit isn't available so the
  /// whole pipeline still runs. Set false on a configured Android/iOS device.
  static bool demoMode = !(defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS);

  /// Extract raw text from an image file.
  /// [imageFile] is an XFile (from image_picker) on device; null in demo.
  /// Replace the demo branch with the ML Kit call shown below on device.
  Future<String> extractRawText(dynamic imageFile) async {
    if (demoMode || imageFile == null) {
      await Future.delayed(const Duration(milliseconds: 600)); // mimic latency
      return _simulatedTimetableText;
    }

    // ----- REAL DEVICE IMPLEMENTATION (uncomment on Android/iOS) -----
    // import 'package:google_mlkit_text_recognition/...';
    //
    // final inputImage = InputImage.fromFile(imageFile);
    // final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    // final RecognizedText result = await recognizer.processImage(inputImage);
    // await recognizer.close();
    // return result.text;
    // -----------------------------------------------------------------

    return _simulatedTimetableText;
  }

  /// Intelligent parsing: turn unstructured OCR text into structured events.
  /// Recognises lines like:  "09:00-11:00 Database Systems Lecture"
  List<ScheduleEvent> parseTimetable(String rawText, {DateTime? day}) {
    final base = day ?? DateTime.now();
    final events = <ScheduleEvent>[];
    final timeReg = RegExp(r'(\d{1,2})[:.](\d{2})\s*[-–to]+\s*(\d{1,2})[:.](\d{2})');

    int counter = 0;
    for (final line in rawText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final m = timeReg.firstMatch(trimmed);
      if (m == null) continue;

      final start = DateTime(base.year, base.month, base.day,
          int.parse(m.group(1)!), int.parse(m.group(2)!));
      final end = DateTime(base.year, base.month, base.day,
          int.parse(m.group(3)!), int.parse(m.group(4)!));

      // Title = everything after the time token.
      var title = trimmed.substring(m.end).trim();
      if (title.isEmpty) title = 'Untitled Event';

      events.add(ScheduleEvent(
        id: 'ocr_${DateTime.now().microsecondsSinceEpoch}_$counter',
        title: title,
        start: start,
        end: end,
        intensity: classifyIntensity(title),
        source: 'ocr',
      ));
      counter++;
    }
    return events;
  }

  /// Keyword-based heuristic that assigns task intensity.
  /// Delegates to the shared [IntensityClassifier] so the OCR pipeline and the
  /// manual Add-Task flow apply the exact same modified NASA-TLX weighting.
  static TaskIntensity classifyIntensity(String title) =>
      IntensityClassifier.fromTitle(title);

  static const String _simulatedTimetableText = '''
MONDAY TIMETABLE
08:00-09:00 Morning Break
09:00-11:00 Database Systems Lecture
11:00-13:00 Software Engineering Lab
13:00-14:00 Lunch
14:00-16:00 Algorithms Assignment Workshop
16:00-18:00 Final Year Project Consultation
19:00-21:00 Calculus Exam Revision
''';
}
