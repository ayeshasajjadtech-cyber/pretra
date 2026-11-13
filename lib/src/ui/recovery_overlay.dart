// lib/src/ui/recovery_overlay.dart

import 'package:flutter/material.dart';
import '../engine/lighting_recovery_engine.dart';

class LightingRecoveryOverlay extends StatelessWidget {
  const LightingRecoveryOverlay({super.key, required this.engine});

  final LightingRecoveryEngine engine;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final state = engine.promptState;
        final isVisible = state != RecoveryPromptState.hidden;

        return IgnorePointer(
          ignoring: !isVisible,
          child: AnimatedOpacity(
            opacity: isVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeInOutCubic,
            child: Align(
              alignment: const Alignment(0, -0.65),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xE60D1929),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: state == RecoveryPromptState.lowLightWarning
                        ? const Color(0xFFFFB300)
                        : const Color(0xFF00E5FF),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (state == RecoveryPromptState.lowLightWarning
                                ? const Color(0xFFFFB300)
                                : const Color(0xFF00E5FF))
                            .withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        state == RecoveryPromptState.lowLightWarning
                            ? Icons.wb_incandescent_outlined
                            : Icons.face_retouching_natural_rounded,
                        color: state == RecoveryPromptState.lowLightWarning
                            ? const Color(0xFFFFB300)
                            : const Color(0xFF00E5FF),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state == RecoveryPromptState.lowLightWarning
                                ? 'OPTIMIZE LIGHTING'
                                : 'ALIGN POSITION',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: state == RecoveryPromptState.lowLightWarning
                                  ? const Color(0xFFFFB300)
                                  : const Color(0xFF00E5FF),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            engine.guidanceMessage,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFE2E8F0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
