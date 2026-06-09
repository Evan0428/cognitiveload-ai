import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../services/app_state.dart';
import '../services/ocr_service.dart';
import '../models/models.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  Future<void> _scan(BuildContext context) async {
    final state = context.read<AppState>();
    dynamic file;

    // On real devices, capture from camera. In demo mode skip straight to
    // the simulated OCR pipeline so it works on web/desktop too.
    if (!OcrService.demoMode) {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 90);
      if (picked != null) file = picked; // XFile; convert to File on device
    }

    final count = await state.scanAndImport(file);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('OCR extracted $count events from the timetable')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final events = state.events;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (events.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear all',
              onPressed: state.clearAll,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: state.loading ? null : () => _scan(context),
                icon: state.loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.document_scanner),
                label: Text(OcrService.demoMode
                    ? 'Scan Timetable (Demo OCR)'
                    : 'Scan Timetable with Camera'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ),
          Expanded(
            child: events.isEmpty
                ? const Center(
                    child: Text('No events yet.\nScan a timetable or add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black45)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: events.length,
                    itemBuilder: (_, i) =>
                        _EventTile(event: events[i], state: state),
                  ),
          ),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    final titleCtrl = TextEditingController();
    TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 10, minute: 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Event',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                    labelText: 'Title', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx, initialTime: start);
                        if (t != null) setSheet(() => start = t);
                      },
                      child: Text('Start: ${start.format(ctx)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx, initialTime: end);
                        if (t != null) setSheet(() => end = t);
                      },
                      child: Text('End: ${end.format(ctx)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (titleCtrl.text.trim().isEmpty) return;
                    final now = DateTime.now();
                    final ev = ScheduleEvent(
                      id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
                      title: titleCtrl.text.trim(),
                      start: DateTime(now.year, now.month, now.day, start.hour,
                          start.minute),
                      end: DateTime(
                          now.year, now.month, now.day, end.hour, end.minute),
                      intensity:
                          OcrService.classifyIntensity(titleCtrl.text),
                      source: 'manual',
                    );
                    context.read<AppState>().addEvent(ev);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Add Event'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final ScheduleEvent event;
  final AppState state;
  const _EventTile({required this.event, required this.state});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.Hm();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: event.intensity.color.withValues(alpha: 0.15),
          child: Icon(
            event.source == 'ocr'
                ? Icons.document_scanner
                : Icons.edit_calendar,
            color: event.intensity.color,
          ),
        ),
        title: Text(event.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${fmt.format(event.start)} – ${fmt.format(event.end)}  •  ${event.source.toUpperCase()}'),
        trailing: PopupMenuButton<TaskIntensity>(
          onSelected: (v) => state.updateIntensity(event.id, v),
          itemBuilder: (_) => TaskIntensity.values
              .map((i) => PopupMenuItem(
                    value: i,
                    child: Row(children: [
                      Icon(Icons.circle, size: 12, color: i.color),
                      const SizedBox(width: 8),
                      Text(i.label),
                    ]),
                  ))
              .toList(),
          child: Chip(
            label: Text(event.intensity.label,
                style: TextStyle(
                    color: event.intensity.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
            backgroundColor: event.intensity.color.withValues(alpha: 0.12),
            side: BorderSide.none,
          ),
        ),
        onLongPress: () => state.removeEvent(event.id),
      ),
    );
  }
}
