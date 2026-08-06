import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart'; // 🟢 用于 PDF 渲染
import 'package:path_provider/path_provider.dart'; // 🟢 用于获取临时目录
import '../models/extracted_task_model.dart';
import '../models/models.dart';

/// 🚀 Schedule Digitization Module — 高级智能化 OCR 结构化服务
class OcrService {
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  static bool demoMode = !(defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS);

  // Shared regexes
  static final RegExp _timeRangeReg = RegExp(
      r'(\d{1,2}[:.]\d{2})\s*(AM|PM)?\s*[-–to至\s]+\s*(\d{1,2}[:.]\d{2})\s*(AM|PM)?',
      caseSensitive: false);
  // Supports DD/MM/YYYY, DD-MM-YYYY, and YYYY-MM-DD
  static final RegExp _dateReg = RegExp(r'(\d{1,4})[/\-](\d{1,2})[/\-](\d{2,4})');

  // 🟢 New regexes for smarter extraction
  static final RegExp _courseCodeReg = RegExp(r'[A-Z]{2,5}[\s-]?\d{3,5}([A-Z]\d{0,2})?', caseSensitive: false);
  static final RegExp _classTypeReg = RegExp(r'\(([LPT]|Lecture|Practical|Tutorial|Lab|TUT|LEC|PRAC|KULIAH|AMALI|MAKMAL)\)', caseSensitive: false);
  // Bare (non-parenthesised) type words, English + Malay.
  static final RegExp _typeWordReg = RegExp(r'\b(lecture|tutorial|practical|lab|kuliah|amali|makmal)\b', caseSensitive: false);
  static final RegExp _roomReg = RegExp(r'^[A-Z]{1,2}\d{2,3}[A-Z]?$|^[A-Z]{1,2}\s[A-Z]$', caseSensitive: false); // e.g. B001, DK Z, TA255, Q105
  // Multi-token hall / venue codes such as "DK ABA", "MAK KP1", "DK Z".
  static final RegExp _venueReg = RegExp(r'^[A-Z]{1,3}(\s+[A-Z0-9]{1,6}){1,3}$');

  static final RegExp _singleTimeReg =
      RegExp(r'(\d{1,2}[:.]\d{2})\s*(AM|PM)?', caseSensitive: false);

  /// 🟢 核心入口：支持 File 对象（图片或 PDF）
  Future<List<ExtractedTaskModel>> recognizeAndStructureFile(File? file) async {
    if (demoMode || file == null) {
      await Future.delayed(const Duration(milliseconds: 800));
      return parseTimetableToUiModels(_simulatedTimetableText);
    }

    try {
      final extension = p.extension(file.path).toLowerCase();
      File imageToProcess;

      if (extension == '.pdf') {
        // PDF 转换逻辑
        imageToProcess = await _convertPdfPageToImage(file);
      } else {
        // 图片直接处理
        imageToProcess = file;
      }

      final InputImage inputImage = InputImage.fromFile(imageToProcess);
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);

      final tasks = parseTimetableFromRecognizedText(recognizedText);
      if (tasks.isNotEmpty) return tasks;

      return parseTimetableToUiModels(recognizedText.text);
    } catch (e) {
      debugPrint("OCR Multi-format Error: $e. Falling back to simulation.");
      return parseTimetableToUiModels(_simulatedTimetableText);
    }
  }

  /// 🟢 将 PDF 的第一页渲染为图片临时文件以便 OCR
  Future<File> _convertPdfPageToImage(File pdfFile) async {
    final document = await PdfDocument.openFile(pdfFile.path);
    final page = await document.getPage(1);

    final pageImage = await page.render(
      width: page.width * 2,
      height: page.height * 2,
      format: PdfPageImageFormat.jpeg,
      quality: 90,
    );

    await page.close();
    await document.close();

    final Directory tempDir = await getTemporaryDirectory();
    final imageFile = File(
        '${tempDir.path}/pdf_scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await imageFile.writeAsBytes(pageImage!.bytes);

    return imageFile;
  }

  // ---------------------------------------------------------------------
  // 🟢 Spatial parser — groups OCR lines into visual "rows" using
  // bounding boxes, so subject + time on the same table row are correctly
  // paired even if ML Kit's raw text order scrambles them.
  // ---------------------------------------------------------------------
  List<ExtractedTaskModel> parseTimetableFromRecognizedText(
      RecognizedText recognizedText) {
    List<TextLine> allLines = [];
    for (final block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }
    if (allLines.isEmpty) return [];

    final rows = _groupLinesIntoRows(allLines);
    // rowTexts[i] = concatenated text of row i in left-to-right order
    final rowTexts = rows.map((r) => r.map((l) => l.text.trim()).join('   ')).toList();

    // 🟢 A GRID / matrix timetable (days down the side, times across the top,
    // each class a multi-line cell) and a plain list are parsed very
    // differently. Rather than guess, run BOTH and keep the richer result —
    // the grid parser only finds day-anchored bands, so on a real list it
    // returns nothing and the list parser wins, and vice-versa.
    final int dayAnchorCount = allLines.where((l) {
      final t = l.text.trim();
      return t.length <= 20 && _extractDay(t) != null;
    }).length;

    final List<ExtractedTaskModel> listTasks = _parseRows(rowTexts);
    final List<ExtractedTaskModel> gridTasks = _parseGridLayout(allLines);

    // Prefer the grid whenever it clearly reconstructed the matrix (several day
    // rows present and it produced results), otherwise take whichever is richer.
    if (gridTasks.isNotEmpty &&
        (dayAnchorCount >= 3 || gridTasks.length >= listTasks.length)) {
      return gridTasks;
    }
    return listTasks;
  }

  // ---------------------------------------------------------------------
  // 🟢 GRID PARSER — general matrix timetable engine.
  //
  // Handles the common structural variants with one pipeline:
  //   • Day labels can run DOWN the side (days = rows) or ACROSS the top
  //     (days = columns); orientation is detected from how the day anchors are
  //     spread out.
  //   • Times can be printed INSIDE each cell ("10:00 AM - 11:00 AM") or only
  //     as an axis header; when a cell has no time we infer it from the header
  //     row/column the cell lines up with.
  //   • English and Malay vocabulary (ISNIN…AHAD, KULIAH/AMALI/TUTORIAL).
  // ---------------------------------------------------------------------
  List<ExtractedTaskModel> _parseGridLayout(List<TextLine> lines) {
    final List<_DayBand> dayAnchors = [];
    final List<_DayBand> dateAnchors = []; // date-only headers ("7/08/2026")
    final List<TextLine> pureTimeLines = [];
    final List<TextLine> otherLines = [];

    for (final l in lines) {
      final t = l.text.trim();
      final day = _extractDay(t);
      if (day != null && t.length <= 22) {
        final dm = _dateReg.firstMatch(t);
        dayAnchors.add(_bandFromLine(l, day, dm != null ? _formatDate(dm) : null));
        continue;
      }
      // A stand-alone date with no day name — becomes a candidate day anchor
      // whose day is DERIVED from the date (e.g. 07/08/2026 → Friday).
      if (t.length <= 14 && _dateReg.hasMatch(t) && !_timeRangeReg.hasMatch(t)) {
        final formatted = _formatDate(_dateReg.firstMatch(t)!);
        final derived = _dayNameFromDate(formatted);
        if (derived != null) {
          dateAnchors.add(_bandFromLine(l, derived, formatted));
        }
        otherLines.add(l); // also kept, for date-attachment when day names win
        continue;
      }
      if (_parseAxisTime(t) != null) {
        pureTimeLines.add(l);
      } else {
        otherLines.add(l);
      }
    }

    // Prefer explicit day names; otherwise fall back to the date-derived
    // anchors so a timetable labelled only with dates still works.
    final List<_DayBand> anchors =
        dayAnchors.length >= 2 ? dayAnchors : dateAnchors;
    if (anchors.length < 2) return [];

    // Orientation: are the day labels spread mostly vertically or horizontally?
    final xs = anchors.map((a) => (a.left + a.right) / 2).toList();
    final ys = anchors.map((a) => a.centerY).toList();
    final double xSpread = xs.reduce(math.max) - xs.reduce(math.min);
    final double ySpread = ys.reduce(math.max) - ys.reduce(math.min);
    final bool daysAreRows = ySpread >= xSpread;

    return daysAreRows
        ? _parseDaysAsRows(anchors, pureTimeLines, otherLines)
        : _parseDaysAsColumns(anchors, pureTimeLines, otherLines);
  }

  _DayBand _bandFromLine(TextLine l, String day, String? date) {
    return _DayBand(
      day: day,
      date: date,
      top: l.boundingBox.top,
      bottom: l.boundingBox.bottom,
      left: l.boundingBox.left,
      right: l.boundingBox.right,
    );
  }

  /// Derives the weekday name from a DD/MM/YYYY string (returns null if it
  /// can't be parsed). Used when a timetable is labelled only with dates.
  String? _dayNameFromDate(String formatted) {
    final parts = formatted.split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    try {
      return _getDayName(DateTime(y, m, d));
    } catch (_) {
      return null;
    }
  }

  /// Orientation A — days down the side, times across the top (UPM / UMT style,
  /// and the original in-cell-time grid).
  List<ExtractedTaskModel> _parseDaysAsRows(List<_DayBand> bands,
      List<TextLine> pureTimeLines, List<TextLine> otherLines) {
    bands.sort((a, b) => a.top.compareTo(b.top));
    final double firstTop = bands.first.top;
    final double dayColRight = bands.map((b) => b.right).reduce(math.max);

    // Time axis = header row above the grid; in-cell times stay as content.
    final axisLines =
        pureTimeLines.where((l) => l.boundingBox.center.dy < firstTop).toList();
    final inCellTimes =
        pureTimeLines.where((l) => l.boundingBox.center.dy >= firstTop).toList();
    final slots = _buildTimeAxis(axisLines, horizontal: true);

    // Vertical extent of the grid (so tables printed BELOW it are ignored).
    double bandGap = _medianGap(bands.map((b) => b.top).toList());
    if (bandGap <= 0) bandGap = bands.last.bottom - bands.first.top + 1;
    final double gridBottom = bands.last.top + bandGap * 1.4;
    // Tolerance must stay SMALL (based on label height, not row spacing) — a
    // large value drags the lower lines of a tall cell into the next day's
    // row, splitting the class's time/lecturer away from its course code.
    final double tol =
        bands.map((b) => b.bottom - b.top).reduce(math.max) * 0.6;

    int bandFor(double y) {
      int idx = 0;
      for (int i = 0; i < bands.length; i++) {
        if (bands[i].top <= y + tol) idx = i;
      }
      return idx;
    }

    // Attach each day's date from the left-column date line under its label
    // (the day label and its date are often separate OCR lines, e.g.
    // "Mon" above "2026-08-03") so every day keeps its OWN date.
    for (final l in otherLines) {
      final t = l.text.trim();
      if (t.length > 14) continue;
      final dm = _dateReg.firstMatch(t);
      if (dm == null || _timeRangeReg.hasMatch(t)) continue;
      final int bi = bandFor(l.boundingBox.center.dy);
      bands[bi].date ??= _formatDate(dm);
    }

    final content = <TextLine>[...otherLines, ...inCellTimes];
    final perBand = List.generate(bands.length, (_) => <TextLine>[]);
    for (final l in content) {
      final b = l.boundingBox;
      if (b.center.dy < firstTop - tol) continue; // header / info above grid
      if (b.center.dy > gridBottom) continue; // tables below the grid
      if (b.center.dx <= dayColRight) continue; // day-label column
      final t = l.text.trim();
      if (t.length <= 14 && _dateReg.hasMatch(t) && !_timeRangeReg.hasMatch(t)) {
        continue; // stray date cell
      }
      perBand[bandFor(b.center.dy)].add(l);
    }

    final String fallbackDate = _todayString();
    final List<ExtractedTaskModel> tasks = [];
    for (int bi = 0; bi < bands.length; bi++) {
      final List<_PendingTask> inferred = [];
      for (final cell in _clusterColumns(perBand[bi])) {
        final subject = _extractSubjectFromCell(cell);
        if (subject.isEmpty) continue;

        final explicit = _timeRangeReg.firstMatch(cell.text);
        if (explicit != null) {
          final r = _composeRange(explicit);
          tasks.add(_mk(subject, bands[bi], r[0], r[1], fallbackDate));
        } else if (slots.isNotEmpty) {
          final r = _inferRange(cell.left, cell.right, slots);
          if (r != null) {
            inferred.add(_PendingTask(subject, r[0], r[1], cell.left));
          }
        }
      }
      // Same subject in adjacent, contiguous columns → one spanning task.
      inferred.sort((a, b) => a.pos.compareTo(b.pos));
      for (final p in _mergePending(inferred)) {
        tasks.add(_mk(p.subject, bands[bi], p.start, p.end, fallbackDate));
      }
    }
    return tasks;
  }

  /// Orientation B — days across the top, times down the side (transposed
  /// weekly view; cells usually carry their own time too).
  List<ExtractedTaskModel> _parseDaysAsColumns(List<_DayBand> days,
      List<TextLine> pureTimeLines, List<TextLine> otherLines) {
    days.sort((a, b) => a.left.compareTo(b.left));
    final double firstLeft = days.first.left;
    final double headerBottom = days.map((d) => d.bottom).reduce(math.max);
    final centers = days.map((d) => (d.left + d.right) / 2).toList();

    int colFor(double x) {
      int idx = 0;
      double best = double.infinity;
      for (int i = 0; i < centers.length; i++) {
        final d = (centers[i] - x).abs();
        if (d < best) {
          best = d;
          idx = i;
        }
      }
      return idx;
    }

    final axisLines = pureTimeLines
        .where((l) => l.boundingBox.center.dx < firstLeft)
        .toList();
    final inCellTimes = pureTimeLines
        .where((l) => l.boundingBox.center.dx >= firstLeft)
        .toList();
    final slots = _buildTimeAxis(axisLines, horizontal: false);

    final content = <TextLine>[...otherLines, ...inCellTimes];
    final perCol = List.generate(days.length, (_) => <TextLine>[]);
    for (final l in content) {
      final b = l.boundingBox;
      if (b.center.dx < firstLeft - 5) continue; // left time axis
      if (b.center.dy <= headerBottom) continue; // day header row
      perCol[colFor(b.center.dx)].add(l);
    }

    final String fallbackDate = _todayString();
    final List<ExtractedTaskModel> tasks = [];
    for (int ci = 0; ci < days.length; ci++) {
      for (final cell in _clusterRows(perCol[ci])) {
        final subject = _extractSubjectFromCell(cell);
        if (subject.isEmpty) continue;

        String? start, end;
        final explicit = _timeRangeReg.firstMatch(cell.text);
        if (explicit != null) {
          final r = _composeRange(explicit);
          start = r[0];
          end = r[1];
        } else if (slots.isNotEmpty) {
          final r = _inferRange(cell.top, cell.bottom, slots);
          if (r != null) {
            start = r[0];
            end = r[1];
          }
        }
        if (start == null || end == null) continue;
        tasks.add(_mk(subject, days[ci], start, end, fallbackDate));
      }
    }
    return tasks;
  }

  /// Splits a day band's lines into class cells by horizontal overlap — one
  /// column = one class; the empty gutters between grid columns separate them.
  List<_GridCell> _clusterColumns(List<TextLine> bandLines) {
    final sorted = List<TextLine>.from(bandLines)
      ..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));

    final List<_GridCell> cells = [];
    for (final line in sorted) {
      _GridCell? target;
      for (final cell in cells) {
        if (cell.horizontallyOverlaps(line)) {
          target = cell;
          break;
        }
      }
      (target ?? (cells..add(_GridCell())).last).add(line);
    }
    return cells;
  }

  /// Splits a day column's lines into class cells vertically. A new cell starts
  /// on a big vertical gap OR when a second time-range line appears (so two
  /// back-to-back classes with no gap are still separated).
  List<_GridCell> _clusterRows(List<TextLine> colLines) {
    final sorted = List<TextLine>.from(colLines)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    if (sorted.isEmpty) return [];

    final heights = sorted
        .map((l) => l.boundingBox.bottom - l.boundingBox.top)
        .toList()
      ..sort();
    final double medH = heights[heights.length ~/ 2];

    final List<_GridCell> cells = [];
    _GridCell? cur;
    double lastBottom = 0;
    bool curHasTime = false;
    for (final l in sorted) {
      final b = l.boundingBox;
      final bool isTime = _timeRangeReg.hasMatch(l.text);
      final double gap = cur == null ? 0 : b.top - lastBottom;
      if (cur == null || gap > medH * 1.6 || (isTime && curHasTime)) {
        cur = _GridCell();
        cells.add(cur);
        curHasTime = false;
      }
      cur.add(l);
      lastBottom = b.bottom;
      if (isTime) curHasTime = true;
    }
    return cells;
  }

  /// Builds a subject label — "COURSECODE (Full Type)" e.g. "CCS3200 (Lecture)".
  /// Falls back to the first meaningful line if no course code is present.
  String _extractSubjectFromCell(_GridCell cell) {
    String? code;
    for (final l in cell.lines) {
      final m = _courseCodeReg.firstMatch(l.text.trim());
      if (m != null) {
        code = m.group(0)!.toUpperCase().replaceAll(RegExp(r'\s+'), '');
        break; // topmost code line wins (course code sits above room/venue)
      }
    }

    final String? typeName = _classTypeName(cell);
    if (code != null) {
      return typeName != null ? "$code ($typeName)" : code;
    }

    for (final l in cell.lines) {
      final t = l.text.trim();
      final cleaned = _clean(l.text);
      if (cleaned.isEmpty) continue;
      if (_timeRangeReg.hasMatch(l.text)) continue; // full time range
      if (_parseAxisTime(t) != null) continue; // bare "10:00 AM", "8am", etc.
      if (_roomReg.hasMatch(t)) continue; // room code (B001, Q105, DK Z…)
      if (_venueReg.hasMatch(t)) continue; // hall/venue code (DK ABA, MAK KP1…)
      return typeName != null ? "$cleaned ($typeName)" : cleaned;
    }
    return '';
  }

  /// Detects and expands a class type from a cell (English + Malay), scanning
  /// top-to-bottom so a real "(Tutorial)"/"KULIAH" marker wins over an
  /// incidental word inside a venue name ("Central Lecture Complex").
  String? _classTypeName(_GridCell cell) {
    for (final l in cell.lines) {
      final paren = _classTypeReg.firstMatch(l.text);
      if (paren != null) return _mapType(paren.group(1)!);
      final word = _typeWordReg.firstMatch(l.text);
      if (word != null) return _mapType(word.group(1)!);
    }
    return null;
  }

  /// Normalises any class-type token to a canonical English word.
  String _mapType(String raw) {
    switch (raw.toUpperCase()) {
      case 'L':
      case 'LEC':
      case 'LECTURE':
      case 'KULIAH':
        return 'Lecture';
      case 'P':
      case 'PRAC':
      case 'PRACTICAL':
      case 'AMALI':
        return 'Practical';
      case 'T':
      case 'TUT':
      case 'TUTORIAL':
        return 'Tutorial';
      case 'LAB':
      case 'MAKMAL':
        return 'Lab';
      default:
        return raw;
    }
  }

  /// Parses a stand-alone time / time-range axis label into [start, endOrEmpty].
  /// Accepts "8.00 - 9.00", "8:00AM - 9:00AM", "8am", "14.00".
  List<String>? _parseAxisTime(String text) {
    final t = text.trim();
    if (t.isEmpty || t.length > 16) return null;

    final range = RegExp(
            r'^(\d{1,2})[:.]?(\d{2})?\s*(am|pm)?\s*[-–]\s*(\d{1,2})[:.]?(\d{2})?\s*(am|pm)?$',
            caseSensitive: false)
        .firstMatch(t);
    if (range != null) {
      return [
        _mkTime(range.group(1)!, range.group(2), range.group(3)),
        _mkTime(range.group(4)!, range.group(5), range.group(6)),
      ];
    }

    final single =
        RegExp(r'^(\d{1,2})[:.]?(\d{2})?\s*(am|pm)?$', caseSensitive: false)
            .firstMatch(t);
    if (single != null) {
      final hasMin = single.group(2) != null;
      final hasAp = single.group(3) != null;
      // A bare integer is only plausibly a time if it's a valid 0–23 hour.
      if (!hasMin && !hasAp && int.parse(single.group(1)!) > 23) return null;
      return [_mkTime(single.group(1)!, single.group(2), single.group(3)), ''];
    }
    return null;
  }

  String _mkTime(String h, String? mm, String? ap) {
    final minutes = (mm == null || mm.isEmpty) ? '00' : mm.padLeft(2, '0');
    final period = (ap == null || ap.isEmpty) ? '' : ap.toUpperCase();
    return period.isEmpty ? "$h:$minutes" : "$h:$minutes $period";
  }

  /// Builds the ordered time axis from header labels. Single-time headers get a
  /// +1h end; two-line headers sharing a position (start row + end row) merge.
  List<_TimeSlot> _buildTimeAxis(List<TextLine> axisLines,
      {required bool horizontal}) {
    final List<_TimeSlot> items = [];
    for (final l in axisLines) {
      final parsed = _parseAxisTime(l.text.trim());
      if (parsed == null) continue;
      final start = parsed[0];
      String end = parsed[1];
      if (end.isEmpty) end = _addMinutesToTimeString(_normalizeAmPm(start), 60);
      final center =
          horizontal ? l.boundingBox.center.dx : l.boundingBox.center.dy;
      items.add(_TimeSlot(start, end, center));
    }
    if (items.isEmpty) return items;
    items.sort((a, b) => a.center.compareTo(b.center));

    final diffs = <double>[];
    for (int i = 1; i < items.length; i++) {
      diffs.add(items[i].center - items[i - 1].center);
    }
    // Representative COLUMN spacing = median of the significant gaps, ignoring
    // the near-zero gaps produced by a two-line header (start row + end row
    // sharing a column position). Otherwise the tolerance collapses to ~0.
    double spacing = 0;
    if (diffs.isNotEmpty) {
      final double maxGap = diffs.reduce(math.max);
      final significant =
          diffs.where((g) => g > maxGap * 0.25).toList()..sort();
      spacing = significant.isEmpty
          ? maxGap
          : significant[significant.length ~/ 2];
    }
    final double mergeTol = spacing > 0 ? spacing * 0.4 : 8;

    final List<_TimeSlot> merged = [];
    for (final it in items) {
      if (merged.isNotEmpty &&
          (it.center - merged.last.center).abs() < mergeTol) {
        final prev = merged.removeLast();
        final s = _toMinutes(prev.start) <= _toMinutes(it.start)
            ? prev.start
            : it.start;
        final e =
            _toMinutes(prev.end) >= _toMinutes(it.end) ? prev.end : it.end;
        merged.add(_TimeSlot(s, e, (prev.center + it.center) / 2));
      } else {
        merged.add(it);
      }
    }
    return merged;
  }

  /// Given a cell's extent [lo, hi] along the axis, returns the [start, end]
  /// spanning every header slot it overlaps (nearest slot if it overlaps none).
  List<String>? _inferRange(double lo, double hi, List<_TimeSlot> slots) {
    if (slots.isEmpty) return null;
    double spacing = 0;
    if (slots.length > 1) {
      final d = <double>[];
      for (int i = 1; i < slots.length; i++) {
        d.add(slots[i].center - slots[i - 1].center);
      }
      d.sort();
      spacing = d[d.length ~/ 2];
    }
    final double tol = spacing > 0 ? spacing * 0.5 : 12;

    final within = slots
        .where((s) => s.center >= lo - tol && s.center <= hi + tol)
        .toList()
      ..sort((a, b) => a.center.compareTo(b.center));
    if (within.isEmpty) {
      final cx = (lo + hi) / 2;
      _TimeSlot? nearest;
      double best = double.infinity;
      for (final s in slots) {
        final dd = (s.center - cx).abs();
        if (dd < best) {
          best = dd;
          nearest = s;
        }
      }
      return nearest == null ? null : [nearest.start, nearest.end];
    }
    return [within.first.start, within.last.end];
  }

  int _toMinutes(String t) {
    final m = RegExp(r'(\d{1,2})[:.](\d{2})\s*(am|pm)?', caseSensitive: false)
        .firstMatch(t);
    if (m == null) return 0;
    int h = int.parse(m.group(1)!);
    final int min = int.parse(m.group(2)!);
    final ap = (m.group(3) ?? '').toLowerCase();
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    return h * 60 + min;
  }

  double _medianGap(List<double> values) {
    final s = List<double>.from(values)..sort();
    final gaps = <double>[];
    for (int i = 1; i < s.length; i++) {
      gaps.add(s[i] - s[i - 1]);
    }
    if (gaps.isEmpty) return 0;
    gaps.sort();
    return gaps[gaps.length ~/ 2];
  }

  /// Merges consecutive pending tasks that share a subject and are time-
  /// contiguous (end of one == start of the next) into a single spanning task.
  List<_PendingTask> _mergePending(List<_PendingTask> items) {
    final List<_PendingTask> out = [];
    for (final p in items) {
      if (out.isNotEmpty &&
          out.last.subject == p.subject &&
          out.last.end == p.start) {
        out.last.end = p.end;
      } else {
        out.add(_PendingTask(p.subject, p.start, p.end, p.pos));
      }
    }
    return out;
  }

  String _todayString() {
    final now = DateTime.now();
    return "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
  }

  ExtractedTaskModel _mk(String subject, _DayBand band, String start, String end,
      String fallbackDate) {
    return ExtractedTaskModel(
      subject: subject,
      day: band.day,
      date: band.date ?? fallbackDate,
      startTime: start,
      endTime: end,
      cognitiveLoadScore: IntensityClassifier.scoreFromTitle(subject),
    );
  }

  /// Normalises a matched time range into ["H:MM AM", "H:MM PM"] strings,
  /// filling in a missing AM/PM from the other end where possible.
  List<String> _composeRange(RegExpMatch m) {
    String startTime = m.group(1)!;
    final String startPeriod = m.group(2) ?? '';
    String endTime = m.group(3)!;
    final String endPeriod = m.group(4) ?? '';

    bool hasM(String s) => s.toUpperCase().contains('M');

    if (startPeriod.isNotEmpty && !hasM(startTime)) startTime += " $startPeriod";
    if (endPeriod.isNotEmpty && !hasM(endTime)) endTime += " $endPeriod";
    // Start missing a period but end has one → assume same half of the day.
    if (!hasM(startTime) && endPeriod.isNotEmpty) startTime += " $endPeriod";
    if (!hasM(startTime) && !hasM(endTime)) {
      startTime += " AM";
      endTime += " AM";
    }
    return [startTime, endTime];
  }

  /// Formats a _dateReg match into DD/MM/YYYY, handling both YYYY-MM-DD and
  /// DD-MM-YYYY orderings.
  String _formatDate(RegExpMatch m) {
    final g1 = m.group(1)!;
    final g2 = m.group(2)!;
    final g3 = m.group(3)!;
    if (g1.length == 4) {
      return "${g3.padLeft(2, '0')}/${g2.padLeft(2, '0')}/$g1"; // YYYY-MM-DD
    }
    return "${g1.padLeft(2, '0')}/${g2.padLeft(2, '0')}/$g3"; // DD-MM-YYYY
  }

  /// Groups OCR lines that sit at roughly the same vertical position into
  /// a single row, then sorts each row left-to-right and rows top-to-bottom.
  List<List<TextLine>> _groupLinesIntoRows(List<TextLine> lines) {
    final sorted = List<TextLine>.from(lines)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final List<List<TextLine>> rows = [];

    for (final line in sorted) {
      final top = line.boundingBox.top;
      final bottom = line.boundingBox.bottom;
      final center = (top + bottom) / 2;
      final height = (bottom - top).abs();

      List<TextLine>? targetRow;
      for (final row in rows) {
        final rowTop =
        row.map((l) => l.boundingBox.top).reduce((a, b) => a < b ? a : b);
        final rowBottom = row
            .map((l) => l.boundingBox.bottom)
            .reduce((a, b) => a > b ? a : b);
        final rowCenter = (rowTop + rowBottom) / 2;

        // Same row if vertical centers are close relative to line height
        if ((center - rowCenter).abs() < height * 0.7) { // Increased threshold for grid layouts
          targetRow = row;
          break;
        }
      }

      if (targetRow != null) {
        targetRow.add(line);
      } else {
        rows.add([line]);
      }
    }

    for (final row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    }
    rows.sort((a, b) {
      final aTop =
      a.map((l) => l.boundingBox.top).reduce((x, y) => x < y ? x : y);
      final bTop =
      b.map((l) => l.boundingBox.top).reduce((x, y) => x < y ? x : y);
      return aTop.compareTo(bTop);
    });

    return rows;
  }

  // ---------------------------------------------------------------------
  // Shared row/line parsing logic — works whether "rows" came from the
  // spatial grouping above or from a plain text split (demo mode / fallback).
  // ---------------------------------------------------------------------
  List<ExtractedTaskModel> _parseRows(List<String> rows) {
    List<ExtractedTaskModel> tasks = [];
    String currentDay = _getDayName(DateTime.now());
    final now = DateTime.now();
    String currentDate =
        "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";

    Set<int> usedRows = {};

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];

      String? detectedDay = _extractDay(row);
      if (detectedDay != null) {
        currentDay = detectedDay;
        final dateMatch = _dateReg.firstMatch(row);
        if (dateMatch != null) {
          String g1 = dateMatch.group(1)!;
          String g2 = dateMatch.group(2)!;
          String g3 = dateMatch.group(3)!;
          
          if (g1.length == 4) {
            // YYYY-MM-DD
            currentDate = "${g3.padLeft(2, '0')}/${g2.padLeft(2, '0')}/$g1";
          } else {
            // DD-MM-YYYY
            currentDate = "${g1.padLeft(2, '0')}/${g2.padLeft(2, '0')}/$g3";
          }
        }
        continue;
      }

      final dateMatch = _dateReg.firstMatch(row);
      if (dateMatch != null && !row.contains(':')) {
        String g1 = dateMatch.group(1)!;
        String g2 = dateMatch.group(2)!;
        String g3 = dateMatch.group(3)!;
        if (g1.length == 4) {
          currentDate = "${g3.padLeft(2, '0')}/${g2.padLeft(2, '0')}/$g1";
        } else {
          currentDate = "${g1.padLeft(2, '0')}/${g2.padLeft(2, '0')}/$g3";
        }
        // No day name on this row — derive the weekday from the date so the
        // following tasks are filed under the correct day.
        currentDay = _dayNameFromDate(currentDate) ?? currentDay;
        continue;
      }

      // Check for full range on one line
      var timeMatch = _timeRangeReg.firstMatch(row);
      String? startTime, endTime, startPeriod, endPeriod;
      int timeMatchEnd = 0;

      if (timeMatch != null) {
        startTime = timeMatch.group(1)!;
        startPeriod = timeMatch.group(2) ?? '';
        endTime = timeMatch.group(3)!;
        endPeriod = timeMatch.group(4) ?? '';
        timeMatchEnd = timeMatch.end;
      } else {
        // Check for split range: "10:00 AM - 11:00" followed by "AM" in next row
        final partialMatch = RegExp(r'(\d{1,2}[:.]\d{2})\s*(AM|PM)?\s*[-–to至\s]+\s*(\d{1,2}[:.]\d{2})', caseSensitive: false).firstMatch(row);
        if (partialMatch != null) {
          startTime = partialMatch.group(1)!;
          startPeriod = partialMatch.group(2) ?? '';
          endTime = partialMatch.group(3)!;
          timeMatchEnd = partialMatch.end;
          
          // Look at next row for "AM/PM"
          if (i + 1 < rows.length && (rows[i+1].trim().toUpperCase() == 'AM' || rows[i+1].trim().toUpperCase() == 'PM')) {
            endPeriod = rows[i+1].trim();
            usedRows.add(i + 1);
          } else {
            endPeriod = '';
          }
        }
      }

      if (startTime == null) continue;

      if (startPeriod!.isNotEmpty && !startTime.toUpperCase().contains('M')) {
        startTime += " $startPeriod";
      }
      if (endPeriod!.isNotEmpty && !endTime!.toUpperCase().contains('M')) {
        endTime += " $endPeriod";
      }
      if (!startTime.toUpperCase().contains('M') &&
          !endTime!.toUpperCase().contains('M')) {
        startTime += " AM";
        endTime += " AM";
      }

      String before = row.substring(0, row.indexOf(startTime.split(' ')[0]));
      String after = row.substring(timeMatchEnd);
      
      // Attempt to extract subject from the same line
      String subject = _clean(after).isNotEmpty ? _clean(after) : _clean(before);

      // 🟢 Improved Vertical Search for Grid Timetables
      // In grids, subject is usually ABOVE the time range.
      if (subject.isEmpty || _roomReg.hasMatch(subject)) {
        String? bestCandidate;
        for (int j = i - 1; j >= 0; j--) {
          if (usedRows.contains(j)) continue;
          
          final candidateRow = rows[j];
          // Stop searching if we hit another time range or day header
          if (_timeRangeReg.hasMatch(candidateRow) || _extractDay(candidateRow) != null) break;
          
          // Only look back up to 5 rows for grid cells
          if (i - j > 6) break;

          String cleanedCandidate = _clean(candidateRow);
          if (cleanedCandidate.isEmpty) continue;

          // Priority 1: High-confidence subject (has Course Code or Class Type L/P/T)
          if (_courseCodeReg.hasMatch(cleanedCandidate) || _classTypeReg.hasMatch(cleanedCandidate)) {
            subject = cleanedCandidate;
            usedRows.add(j);
            break; 
          }
          
          // Priority 2: Possible subject (avoiding obvious rooms and short headers)
          if (bestCandidate == null && !_roomReg.hasMatch(cleanedCandidate) && cleanedCandidate.length > 3) {
            bestCandidate = cleanedCandidate;
          }
        }
        
        if (subject.isEmpty && bestCandidate != null) {
          subject = bestCandidate;
        }
      }

      if (subject.isEmpty) subject = 'Scheduled Task';

      tasks.add(ExtractedTaskModel(
        subject: subject,
        day: currentDay,
        date: currentDate,
        startTime: startTime,
        endTime: endTime!,
        cognitiveLoadScore: IntensityClassifier.scoreFromTitle(subject),
      ));
    }

    // ---------------------------------------------------------------
    // 🟢 Last-resort fallback: no full time RANGE was found anywhere.
    // Instead of hardcoding start/end/score, we:
    //   1. Scan every row for loose single-time fragments (e.g. "9:00 AM")
    //      and use two of them as start/end if found.
    //   2. If only one time fragment exists, use it as the start and
    //      derive an end time by adding a default duration.
    //   3. Compute the score from the detected subject text via
    //      classifyIntensityToScore(), same as the main path.
    // Only if literally NO time-like text exists anywhere do we fall back
    // to a fixed placeholder — genuinely nothing to derive from at that point.
    // ---------------------------------------------------------------
    if (tasks.isEmpty && rows.any((l) => l.trim().isNotEmpty)) {
      final validLine = _clean(rows.firstWhere((l) => l.trim().isNotEmpty));

      final List<String> foundTimes = [];
      for (final row in rows) {
        final match = _singleTimeReg.firstMatch(row);
        if (match != null) {
          String t = match.group(1)!;
          String period = match.group(2) ?? '';
          if (period.isNotEmpty) t += " $period";
          foundTimes.add(t);
        }
      }

      String startTime;
      String endTime;

      if (foundTimes.length >= 2) {
        // Found two separate time mentions — treat as start/end.
        startTime = _normalizeAmPm(foundTimes[0]);
        endTime = _normalizeAmPm(foundTimes[1]);
      } else if (foundTimes.length == 1) {
        // Only one time found — use it as start, derive end by adding
        // a default duration (duration is assumed, but the start time
        // itself is still real detected data, not a guess).
        startTime = _normalizeAmPm(foundTimes[0]);
        endTime = _addMinutesToTimeString(startTime, 90); // default 1.5h block
      } else {
        // Truly no time-like text anywhere in the image — nothing to derive from.
        startTime = "09:00 AM";
        endTime = "10:30 AM";
      }

      if (validLine.isNotEmpty) {
        tasks.add(ExtractedTaskModel(
          subject: validLine,
          day: currentDay,
          date: currentDate,
          startTime: startTime,
          endTime: endTime,
          cognitiveLoadScore: IntensityClassifier.scoreFromTitle(validLine),
        ));
      }
    }

    return tasks;
  }

  /// Legacy flat-text entry point (used for demo mode + fallback).
  List<ExtractedTaskModel> parseTimetableToUiModels(String rawText) {
    final rows =
    rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return _parseRows(rows);
  }

  /// Strips list markers / table borders without eating letters-adjacent
  /// digits (e.g. "3D Printing", "Room 101" survive intact now).
  String _clean(String s) {
    String cleaned = s.trim();
    cleaned = cleaned.replaceFirst(
        RegExp(r'^[\|\+\=_\[\]\(\)\{\}•\-\.\s]*(\d+[\.\)])?[\|\+\=_\[\]\(\)\{\}•\-\.\s]*'),
        '');
    cleaned = cleaned.replaceFirst(RegExp(r'[\|\+\=_\[\]\(\)\{\}\-\.\s]+$'), '');
    cleaned = cleaned.trim();
    if (!RegExp(r'[a-zA-Z]').hasMatch(cleaned)) return "";
    return cleaned;
  }

  /// Ensures a time string has an AM/PM suffix (defaults to AM if ambiguous).
  String _normalizeAmPm(String time) {
    if (time.toUpperCase().contains('M')) return time;
    return "$time AM";
  }

  /// Adds [minutes] to a "H:MM AM/PM" style string and returns a new one.
  String _addMinutesToTimeString(String time, int minutes) {
    final match = RegExp(r'(\d{1,2})[:.](\d{2})\s*(AM|PM)?', caseSensitive: false)
        .firstMatch(time);
    if (match == null) return time;

    int hour = int.parse(match.group(1)!);
    int minute = int.parse(match.group(2)!);
    String period = (match.group(3) ?? 'AM').toUpperCase();

    // Convert to 24h for arithmetic
    int hour24 = hour % 12;
    if (period == 'PM') hour24 += 12;

    int totalMinutes = hour24 * 60 + minute + minutes;
    totalMinutes %= (24 * 60);

    int newHour24 = totalMinutes ~/ 60;
    int newMinute = totalMinutes % 60;

    String newPeriod = newHour24 >= 12 ? 'PM' : 'AM';
    int newHour12 = newHour24 % 12;
    if (newHour12 == 0) newHour12 = 12;

    return "${newHour12.toString().padLeft(2, '0')}:${newMinute.toString().padLeft(2, '0')} $newPeriod";
  }

  String _getDayName(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  /// 🟢 NASA-TLX 报告规范之关键词权重矩阵算法
  int classifyIntensityToScore(String title) => IntensityClassifier.scoreFromTitle(title);

  /// 辅助方法：星期侦测器 — matches full names anywhere, plus abbreviations
  /// ("Mon", "Tue", …) when the text is short (as in a grid's day column).
  String? _extractDay(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 35) return null;
    final String lower = trimmed.toLowerCase();

    const full = {
      'monday': 'Monday',
      'tuesday': 'Tuesday',
      'wednesday': 'Wednesday',
      'thursday': 'Thursday',
      'friday': 'Friday',
      'saturday': 'Saturday',
      'sunday': 'Sunday',
      // Malay (Bahasa Melayu) day names.
      'isnin': 'Monday',
      'selasa': 'Tuesday',
      'rabu': 'Wednesday',
      'khamis': 'Thursday',
      'jumaat': 'Friday',
      'jumat': 'Friday',
      'sabtu': 'Saturday',
      'ahad': 'Sunday',
    };
    for (final e in full.entries) {
      if (lower.contains(e.key)) return e.value;
    }

    // Abbreviations only for short cells, to avoid false hits inside prose.
    if (trimmed.length <= 14) {
      const abbr = {
        'mon': 'Monday',
        'tue': 'Tuesday',
        'wed': 'Wednesday',
        'thu': 'Thursday',
        'fri': 'Friday',
        'sat': 'Saturday',
        'sun': 'Sunday',
      };
      for (final e in abbr.entries) {
        if (RegExp('^${e.key}\\b', caseSensitive: false).hasMatch(lower)) {
          return e.value;
        }
      }
    }
    return null;
  }

  void dispose() {
    _textRecognizer.close();
  }

  static const String _simulatedTimetableText = '''
21/07/2026
Math test
1.00pm - 3.00pm
Gym
5.00pm - 6.30pm
''';
}

/// 🟢 A day anchor in a grid timetable — a day label ("Mon 2026-08-03" /
/// "ISNIN" / "Monday 30 Mar") with its resolved day name, optional date, and
/// bounding box (used as a row band when days are rows, or a column when days
/// are columns).
class _DayBand {
  final String day;
  String? date;
  final double top;
  final double bottom;
  final double left;
  final double right;

  _DayBand({
    required this.day,
    required this.date,
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  double get centerY => (top + bottom) / 2;
}

/// 🟢 One header time slot on the axis, with its axis position (x for a column
/// axis, y for a row axis) and its [start, end] times.
class _TimeSlot {
  final String start;
  final String end;
  final double center;
  _TimeSlot(this.start, this.end, this.center);
}

/// 🟢 A task awaiting a possible merge with an adjacent same-subject cell.
class _PendingTask {
  final String subject;
  final String start;
  String end;
  final double pos;
  _PendingTask(this.subject, this.start, this.end, this.pos);
}

/// 🟢 One class cell of a matrix timetable — the OCR lines that make up a
/// single class block (course code + room + lecturer + time).
class _GridCell {
  final List<TextLine> lines = [];

  double left = double.infinity;
  double right = double.negativeInfinity;
  double top = double.infinity;
  double bottom = double.negativeInfinity;

  double get width => right - left;

  /// Lines joined top-to-bottom (kept sorted as they're added).
  String get text => lines.map((l) => l.text.trim()).join(' ');

  void add(TextLine line) {
    lines.add(line);
    final b = line.boundingBox;
    left = math.min(left, b.left);
    right = math.max(right, b.right);
    top = math.min(top, b.top);
    bottom = math.max(bottom, b.bottom);
    lines.sort((a, c) => a.boundingBox.top.compareTo(c.boundingBox.top));
  }

  /// True when [line] belongs to the same column as this cell. A line joins if
  /// it shares meaningful x-overlap OR — crucially for narrow wrapped lines
  /// like "(T)", "Yun", "DK ABA", "2:00 PM" — if its centre sits inside the
  /// cell's x-range. Grid gutters keep neighbouring columns non-overlapping and
  /// centre-disjoint, so distinct classes still stay in separate cells.
  bool horizontallyOverlaps(TextLine line) {
    final b = line.boundingBox;
    final double overlap = math.min(right, b.right) - math.max(left, b.left);
    final double minWidth = math.min(width, b.right - b.left);
    if (overlap > (minWidth <= 0 ? 1 : minWidth) * 0.2) return true;
    final double c = b.center.dx;
    return c >= left && c <= right;
  }
}