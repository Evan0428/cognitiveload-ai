import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ready Player Me avatar service (Chua Yi Zhe — 3D avatar).
///
/// Stores the user's RPM avatar `.glb` URL locally + in Firestore, and exposes
/// it reactively so every avatar widget updates the moment it changes. Also
/// derives RPM's free 2D portrait render (`<id>.png`) for small avatars, so we
/// don't load a heavy 3D model just to show a profile circle.
class RpmService {
  static const _prefsKey = 'rpmAvatarUrl';

  /// Your Ready Player Me subdomain for the personalised 3D avatar builder.
  ///
  /// ⚠️ RPM retired the old public `demo` subdomain, so you must create your
  /// own FREE one at https://studio.readyplayer.me (no card needed) and put it
  /// here — e.g. 'cognitiveload'. Until then the builder shows a friendly
  /// notice and the user can pick a ready-made 3D character instead.
  static const String subdomain = ''; // ← paste your free subdomain here

  static bool get hasSubdomain => subdomain.trim().isNotEmpty;

  static String get builderUrl =>
      'https://${subdomain.trim()}.readyplayer.me/avatar?frameApi';

  /// Ready-made 3D characters (Google's public model-viewer sample assets).
  /// These need no account and work immediately — used as the default 3D
  /// assistant and offered as a picker.
  /// Standing human / robot assistants — each with its own voice character
  /// ([pitch]/[rate] shape the delivery; [voice]+[locale] request a specific
  /// system voice when the device has it, otherwise pitch/rate still apply).
  static const List<
      ({
        String name,
        String url,
        String emoji,
        String persona,
        double pitch,
        double rate,
        String? voice,
        String locale,
      })> characters = [
    (
      name: 'Robo',
      emoji: '🤖',
      persona: 'Cheerful robot',
      url: 'https://modelviewer.dev/shared-assets/models/RobotExpressive.glb',
      pitch: 1.35, // bright, upbeat robot
      rate: 0.46,
      voice: null,
      locale: 'en-US',
    ),
    (
      name: 'Nova',
      emoji: '🦾',
      persona: 'Calm android',
      url:
          'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/2.0/BrainStem/glTF-Binary/BrainStem.glb',
      pitch: 0.72, // deep, machine-like
      rate: 0.40,
      voice: null,
      locale: 'en-US',
    ),
    (
      name: 'Astro',
      emoji: '🧑‍🚀',
      persona: 'Steady explorer',
      url: 'https://modelviewer.dev/shared-assets/models/Astronaut.glb',
      pitch: 1.0,
      rate: 0.45,
      voice: 'Daniel', // British male on iOS
      locale: 'en-GB',
    ),
    (
      name: 'Mia',
      emoji: '👩',
      persona: 'Warm coach',
      url: 'https://threejs.org/examples/models/gltf/Michelle.glb',
      pitch: 1.15,
      rate: 0.48,
      voice: 'Samantha', // US female on iOS
      locale: 'en-US',
    ),
    (
      name: 'Alex',
      emoji: '🧍',
      persona: 'Friendly buddy',
      url: 'https://threejs.org/examples/models/gltf/Xbot.glb',
      pitch: 0.95,
      rate: 0.47,
      voice: 'Karen', // AU voice on iOS
      locale: 'en-AU',
    ),
    (
      name: 'Max',
      emoji: '🕴️',
      persona: 'Focused mentor',
      url: 'https://threejs.org/examples/models/gltf/Soldier.glb',
      pitch: 0.85, // firm and low
      rate: 0.43,
      voice: null,
      locale: 'en-US',
    ),
  ];

  /// Voice settings for the character the user currently has selected.
  static ({double pitch, double rate, String? voice, String locale})
      get currentVoice {
    final url = effectiveUrl;
    for (final c in characters) {
      if (c.url == url) {
        return (pitch: c.pitch, rate: c.rate, voice: c.voice, locale: c.locale);
      }
    }
    return (pitch: 1.0, rate: 0.46, voice: null, locale: 'en-US');
  }

  /// The 3D model shown when the user hasn't made a personalised avatar yet,
  /// so the assistant is ALWAYS 3D rather than falling back to a flat cartoon.
  static String get defaultCharacterUrl => characters.first.url;

  /// The 3D model to render right now — the user's pick, else the default.
  /// Never null, so the app is 3D everywhere (no flat-cartoon fallback).
  static String get effectiveUrl {
    final u = avatarUrl.value;
    return (u != null && u.isNotEmpty) ? u : defaultCharacterUrl;
  }

  /// Reactive current avatar `.glb` URL (null = user hasn't made one → the app
  /// falls back to the fluttermoji cartoon).
  static final ValueNotifier<String?> avatarUrl = ValueNotifier<String?>(null);

  /// Load the saved URL (local first, then cloud) into [avatarUrl].
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString(_prefsKey);
    if (local != null && local.isNotEmpty) {
      avatarUrl.value = local;
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final url = doc.data()?['rpmAvatarUrl'] as String?;
      if (url != null && url.isNotEmpty) {
        await prefs.setString(_prefsKey, url);
        avatarUrl.value = url;
      }
    } catch (e) {
      debugPrint('RPM cloud load failed: $e');
    }
  }

  /// Persist a freshly-created avatar URL (local + cloud) and publish it.
  Future<void> save(String glbUrl) async {
    avatarUrl.value = glbUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, glbUrl);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'rpmAvatarUrl': glbUrl}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('RPM cloud save failed (kept local): $e');
    }
  }

  /// RPM's free 2D portrait render for a `.glb` URL, e.g.
  /// https://models.readyplayer.me/<id>.glb → https://models.readyplayer.me/<id>.png
  static String? portraitUrl(String? glbUrl, {int size = 256}) {
    // Only Ready Player Me models have a matching 2D portrait render.
    if (glbUrl == null ||
        !glbUrl.endsWith('.glb') ||
        !glbUrl.contains('readyplayer.me')) return null;
    final png = glbUrl.substring(0, glbUrl.length - 4);
    return '$png.png?size=$size';
  }
}
