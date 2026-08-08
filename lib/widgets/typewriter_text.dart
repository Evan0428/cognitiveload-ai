import 'dart:async';
import 'package:flutter/material.dart';

/// Reveals text one word at a time, like a chat message being typed — used by
/// the avatar assistant so its advice appears as if it's talking to you.
class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final Duration wordDelay;
  final VoidCallback? onDone;

  const TypewriterText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.wordDelay = const Duration(milliseconds: 200),
    this.onDone,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  List<String> _words = const [];
  int _shown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(TypewriterText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _start();
  }

  void _start() {
    _timer?.cancel();
    _words = widget.text.split(RegExp(r'\s+'));
    _shown = 0;
    _timer = Timer.periodic(widget.wordDelay, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_shown >= _words.length) {
        t.cancel();
        widget.onDone?.call();
        return;
      }
      setState(() => _shown++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _words.take(_shown).join(' '),
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}
