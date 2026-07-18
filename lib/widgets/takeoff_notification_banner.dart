import 'dart:async';

import 'package:flutter/material.dart';
import '../models/aircraft_contact.dart';

/// Generic temporary top-banner used for in-app notifications.
/// It animates in from above, stays briefly, then slides out.
class InAppNotificationBanner extends StatefulWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String message;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final Duration displayDuration;

  const InAppNotificationBanner({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.message,
    required this.onTap,
    required this.onDismiss,
    this.displayDuration = const Duration(seconds: 6),
  });

  @override
  State<InAppNotificationBanner> createState() =>
      _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<InAppNotificationBanner> {
  static const _animationDuration = Duration(milliseconds: 260);
  Timer? _autoDismissTimer;
  bool _visible = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = true);
    });
    _autoDismissTimer = Timer(widget.displayDuration, _startDismiss);
  }

  void _startDismiss() {
    if (!mounted || _dismissing) return;
    _dismissing = true;
    setState(() => _visible = false);
    Future.delayed(_animationDuration, () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: _animationDuration,
      curve: Curves.easeOutCubic,
      offset: _visible ? Offset.zero : const Offset(0, -1),
      child: AnimatedOpacity(
        duration: _animationDuration,
        curve: Curves.easeOut,
        opacity: _visible ? 1 : 0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              widget.onTap();
              _startDismiss();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        Icon(widget.icon, color: widget.accentColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 18),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    splashRadius: 18,
                    onPressed: _startDismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Backward-compatible wrapper for helicopter takeoff events.
class TakeoffNotificationBanner extends StatelessWidget {
  final TakeoffEvent event;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const TakeoffNotificationBanner({
    super.key,
    required this.event,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final kindLabel = event.aircraft.estimatedKindLabel;
    final tailNumber = event.aircraft.tailNumberLabel;
    return InAppNotificationBanner(
      icon: Icons.flight_takeoff,
      accentColor: Colors.amberAccent,
      title: 'Air traffic alert',
      message: tailNumber.isNotEmpty
          ? '$kindLabel $tailNumber taking off nearby'
          : '$kindLabel taking off nearby',
      onTap: onTap,
      onDismiss: onDismiss,
    );
  }
}
