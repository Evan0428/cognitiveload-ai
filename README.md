# CognitiveLoad AI — Combined System (First Version)

A Flutter mobile app implementing **both** team modules of the
*Cognitive Load & Mental Stress Management System* in one application.

| Module | Owner | What it does |
|--------|-------|--------------|
| Schedule Digitization | **Lim Kah Jun** | OCR-scan timetables, parse into events, score workload density (NASA-TLX-inspired), fire workload warnings |
| Physiological Monitoring | **Chua Yi Zhe** | Read HR / HRV / Sleep / Steps from HealthKit, compute readiness, haptic alerts |
| Fusion (new) | Combined | Merges schedule demand + body readiness into one Cognitive Load score |

## How to run

```bash
cd cognitiveload_ai
flutter pub get
flutter run            # phone, emulator, or: flutter run -d chrome
```

The app launches in **Demo Mode** automatically on web/desktop (and wherever
ML Kit / HealthKit aren't configured), using simulated OCR text and simulated
biometrics so the entire pipeline works immediately. On a configured
Android/iOS device, set `OcrService.demoMode = false` and
`HealthService.demoMode = false`, then uncomment the marked real-device blocks.

## Function checklist (traced to the reports)

**Lim — Schedule module**
- [x] Capture / upload timetable image (camera via `image_picker`)
- [x] OCR text extraction (Google ML Kit on device; simulated in demo)
- [x] Intelligent parsing: times + subjects → structured `ScheduleEvent`s
- [x] Multi-source aggregation (OCR + manual, tagged by `source`)
- [x] Task-density / Workload Score (weight × duration)
- [x] Keyword intensity classification (modified NASA-TLX weighting)
- [x] Workload-warning alerts above threshold
- [x] Local offline persistence (`shared_preferences`)

**Chua — Physiological module**
- [x] HealthKit permission request + biometric sync
- [x] Heart Rate, HRV, Sleep, Steps retrieval
- [x] Physiological Readiness (cognitive capacity) score
- [x] Recovery / break recommendations
- [x] Notification + haptic alert hook (Taptic Engine on device)

**Combined**
- [x] Fused cognitive-load gauge (workload + readiness)
- [x] Load levels: Balanced → Elevated → High → Overload
- [x] Dashboard, Schedule, and Wellbeing screens

## Where to plug in real device code

Search the codebase for `REAL DEVICE IMPLEMENTATION` — each block shows the
exact ML Kit / HealthKit / notifications call to uncomment.

## File map
```
lib/
  main.dart                       App shell + bottom nav
  models/models.dart              ScheduleEvent, PhysiologicalSnapshot, intensity
  services/
    ocr_service.dart              OCR + timetable parsing (Lim)
    health_service.dart           HealthKit biometrics (Chua)
    cognitive_load_engine.dart    Workload, readiness & fusion math
    app_state.dart                Provider state, persistence, orchestration
    notification_service.dart     Alerts / haptics
  screens/
    dashboard_screen.dart         Combined load gauge + alerts
    schedule_screen.dart          Scan, list, edit intensity
    wellbeing_screen.dart         Readiness detail
  theme/app_theme.dart
```
