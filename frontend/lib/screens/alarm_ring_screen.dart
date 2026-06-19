import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';

/// Full-screen alarm UI shown when a scheduled reminder rings.
///
/// This screen is pushed by main.dart when [Alarm.ringStream] emits.
/// The user MUST press Dismiss — the back gesture is disabled so they
/// can't accidentally swipe away without stopping the alarm.
class AlarmRingScreen extends StatefulWidget {
  const AlarmRingScreen({super.key, required this.alarmSettings});
  final AlarmSettings alarmSettings;

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await Alarm.stop(widget.alarmSettings.id);
    if (mounted) Navigator.pop(context);
  }

  String _formattedTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    // Prevent back-gesture so the alarm can't be dismissed accidentally
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0030),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Pulsing alarm icon ──────────────────────────────────────
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final scale = 1.0 + _pulse.value * 0.12;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF6200EE)
                              .withValues(alpha: 0.18 + _pulse.value * 0.10),
                          border: Border.all(
                            color: const Color(0xFF9B7FFF),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6200EE)
                                  .withValues(alpha: 0.55),
                              blurRadius: 32 + _pulse.value * 20,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.alarm_rounded,
                          color: Colors.white,
                          size: 68,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 36),

                // ── ALARM label ─────────────────────────────────────────────
                const Text(
                  'ALARM',
                  style: TextStyle(
                    color: Color(0xFF9B7FFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),

                const SizedBox(height: 14),

                // ── Time ────────────────────────────────────────────────────
                Text(
                  _formattedTime(widget.alarmSettings.dateTime),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 20),

                // ── Reminder title ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    widget.alarmSettings.notificationSettings.body,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                const SizedBox(height: 70),

                // ── Dismiss button ──────────────────────────────────────────
                SizedBox(
                  width: 240,
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: _dismiss,
                    icon: const Icon(
                      Icons.alarm_off_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    label: const Text(
                      'DISMISS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6200EE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 10,
                      shadowColor:
                          const Color(0xFF6200EE).withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
