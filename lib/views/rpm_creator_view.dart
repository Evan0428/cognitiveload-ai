import 'package:flutter/material.dart';
import '../services/assistant_service.dart';
import '../services/rpm_service.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_view.dart';

/// 3D assistant setup (Chua Yi Zhe).
///
/// The user picks a standing human/robot character; each one has its own voice
/// and greets in it when tapped. Shown as an onboarding step and re-openable
/// from Settings.
class RpmCreatorView extends StatefulWidget {
  final bool onboarding;
  const RpmCreatorView({super.key, this.onboarding = false});

  @override
  State<RpmCreatorView> createState() => _RpmCreatorViewState();
}

class _RpmCreatorViewState extends State<RpmCreatorView> {
  final RpmService _service = RpmService();
  final AssistantService _assistant = AssistantService();

  @override
  void dispose() {
    _assistant.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.onboarding,
        title: Text(widget.onboarding ? 'Choose Your 3D Assistant' : 'My 3D Avatar'),
        actions: [
          if (widget.onboarding)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Skip', style: TextStyle(color: AppTheme.inkSoft)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Live 3D preview of the current selection.
          Center(
            child: Container(
              height: 220,
              width: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppTheme.indigo.withValues(alpha: 0.16),
                  AppTheme.indigo.withValues(alpha: 0.0),
                ]),
              ),
              child: const AvatarView(
                  size: 220, circle: false, allowSpin: true),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Drag to spin your assistant',
                style: TextStyle(fontSize: 12, color: AppTheme.inkFaint)),
          ),
          const SizedBox(height: 24),

          const Text('Pick a 3D character',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.ink)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in RpmService.characters)
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 40 - 24) / 3,
                  child: _CharacterTile(
                    emoji: c.emoji,
                    name: c.name,
                    persona: c.persona,
                    selected: RpmService.effectiveUrl == c.url,
                    onTap: () async {
                      await _service.save(c.url);
                      if (mounted) setState(() {});
                      // Greet in this character's own voice so you can hear it.
                      _assistant.speak(
                          "Hi, I'm ${c.name}, your ${c.persona.toLowerCase()}.");
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (widget.onboarding)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded),
                label: const Text('Start My Journey'),
                onPressed: () async {
                  // Ensure an avatar is set even if they didn't tap one.
                  if ((RpmService.avatarUrl.value ?? '').isEmpty) {
                    await _service.save(RpmService.defaultCharacterUrl);
                  }
                  if (mounted) Navigator.pop(context);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CharacterTile extends StatelessWidget {
  final String emoji, name, persona;
  final bool selected;
  final VoidCallback onTap;
  const _CharacterTile(
      {required this.emoji,
      required this.name,
      required this.persona,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.indigo.withValues(alpha: 0.08)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? AppTheme.indigo : AppTheme.line,
              width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(height: 4),
            Text(name,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? AppTheme.indigo : AppTheme.ink)),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(persona,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 10, height: 1.2, color: AppTheme.inkFaint)),
            ),
            const SizedBox(height: 4),
            Icon(Icons.volume_up_rounded,
                size: 14,
                color: selected ? AppTheme.indigo : AppTheme.inkFaint),
          ],
        ),
      ),
    );
  }
}

