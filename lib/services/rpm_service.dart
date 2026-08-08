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
    if (glbUrl == null || !glbUrl.endsWith('.glb')) return null;
    final png = glbUrl.substring(0, glbUrl.length - 4);
    return '$png.png?size=$size';
  }
}
