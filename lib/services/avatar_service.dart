import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttermoji/fluttermoji.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

/// Virtual Avatar service (Chua Yi Zhe).
///
/// Runs on-device ML Kit face detection on a selfie, samples the user's skin
/// tone, and seeds a customizable cartoon avatar (fluttermoji) to resemble
/// them. The user can then refine every feature. Avatar config is persisted
/// locally and mirrored to the Firestore user profile so it follows them
/// across devices.
class AvatarService {
  /// fluttermoji's 7 skin swatches, in index order (see fluttermoji skin.dart).
  static const List<int> _skinHex = [
    0xFD9841, // 0 Tanned
    0xF8D25C, // 1 Yellow
    0xFFDBB4, // 2 White
    0xEDB98A, // 3 Pale
    0xD08B5B, // 4 Brown
    0xAE5D29, // 5 DarkBrown
    0x614335, // 6 Black
  ];

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(enableClassification: true),
  );

  FluttermojiController get _controller =>
      Get.isRegistered<FluttermojiController>()
          ? Get.find<FluttermojiController>()
          : Get.put(FluttermojiController());

  /// True once the user has created/customised an avatar.
  Future<bool> hasAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fluttermojiSelectedOptions') != null;
  }

  /// Detect a face in [image], sample skin tone, and seed the avatar.
  /// Returns the chosen skin index, or null if no usable face was found.
  Future<int?> seedFromSelfie(File image) async {
    try {
      final faces =
          await _detector.processImage(InputImage.fromFilePath(image.path));
      final decoded = img.decodeImage(await image.readAsBytes());
      if (decoded == null) return null;

      final Rect? box = faces.isNotEmpty ? faces.first.boundingBox : null;
      final sampled = _sampleSkinTone(decoded, box);
      final idx = _nearestSkinIndex(sampled);
      await _applySkin(idx);
      return idx;
    } catch (e) {
      debugPrint('Avatar face seed failed: $e');
      return null;
    }
  }

  /// Set the avatar's skin swatch and persist (local + cloud).
  Future<void> _applySkin(int index) async {
    final c = _controller;
    final options = await c.getFluttermojiOptions();
    options['skinColor'] = index;
    c.selectedOptions = Map<String?, dynamic>.from(options);
    await c.setFluttermoji(); // persists + sets the reactive fluttermoji.value
    c.updatePreview(); // force-regenerate the SVG so the preview refreshes
    await saveToCloud();
  }

  /// Average the skin-coloured pixels in the cheek region of the face box.
  int _sampleSkinTone(img.Image im, Rect? box) {
    int x0, y0, x1, y1;
    if (box != null) {
      x0 = (box.left + box.width * 0.30).round().clamp(0, im.width - 1);
      x1 = (box.left + box.width * 0.70).round().clamp(0, im.width - 1);
      y0 = (box.top + box.height * 0.50).round().clamp(0, im.height - 1);
      y1 = (box.top + box.height * 0.80).round().clamp(0, im.height - 1);
    } else {
      x0 = (im.width * 0.40).round();
      x1 = (im.width * 0.60).round();
      y0 = (im.height * 0.40).round();
      y1 = (im.height * 0.60).round();
    }

    int r = 0, g = 0, b = 0, n = 0;
    for (int y = y0; y <= y1; y += 2) {
      for (int x = x0; x <= x1; x += 2) {
        final p = im.getPixel(x, y);
        final rr = p.r.toInt(), gg = p.g.toInt(), bb = p.b.toInt();
        final mx = max(rr, max(gg, bb));
        if (mx < 40 || mx > 250) continue; // skip shadows / blown highlights
        // Loose skin heuristic: red channel dominant.
        if (rr < bb) continue;
        r += rr;
        g += gg;
        b += bb;
        n++;
      }
    }
    if (n == 0) return 0xEDB98A; // fall back to a neutral tone
    return ((r ~/ n) << 16) | ((g ~/ n) << 8) | (b ~/ n);
  }

  int _nearestSkinIndex(int rgb) {
    final r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < _skinHex.length; i++) {
      final sr = (_skinHex[i] >> 16) & 0xFF,
          sg = (_skinHex[i] >> 8) & 0xFF,
          sb = _skinHex[i] & 0xFF;
      final d = pow(r - sr, 2) + pow(g - sg, 2) + pow(b - sb, 2);
      if (d < bestDist) {
        bestDist = d.toDouble();
        best = i;
      }
    }
    return best;
  }

  /// Mirror the current avatar config to the Firestore user profile.
  Future<void> saveToCloud() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final options = prefs.getString('fluttermojiSelectedOptions');
    if (options == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'avatarOptions': options}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Avatar cloud save failed (kept local): $e');
    }
  }

  /// Restore the avatar from Firestore on a fresh device/install. Does not
  /// clobber a locally-edited avatar.
  Future<void> loadFromCloud() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('fluttermojiSelectedOptions') != null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final options = doc.data()?['avatarOptions'] as String?;
      if (options == null) return;
      await prefs.setString('fluttermojiSelectedOptions', options);
      await prefs.setString('fluttermoji',
          FluttermojiFunctions().decodeFluttermojifromString(options));
      if (Get.isRegistered<FluttermojiController>()) {
        // restoreState() is declared `void ... async`, so it can't be awaited.
        Get.find<FluttermojiController>().restoreState();
      }
    } catch (e) {
      debugPrint('Avatar cloud load failed: $e');
    }
  }

  void dispose() => _detector.close();
}
