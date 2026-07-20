import 'package:flutter/material.dart';

// ===========================================================================
// Tiny motion helpers — used to make screens feel alive (no packages needed).
// ===========================================================================

/// Fades + slides its child in after [delayMs].
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.delayMs, required this.child});
  final int delayMs;
  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.07),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Pops its child in with a springy scale after [delayMs].
class PopIn extends StatefulWidget {
  const PopIn({super.key, required this.delayMs, required this.child});
  final int delayMs;
  final Widget child;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: AnimatedScale(
        scale: _shown ? 1 : 0.5,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack, // springy overshoot
        child: widget.child,
      ),
    );
  }
}
