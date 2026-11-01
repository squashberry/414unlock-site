import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StartupLogoAnimation extends StatefulWidget {
  final AppBrandVariant variant;
  final VoidCallback onComplete;
  final String subtitle;

  const StartupLogoAnimation({
    super.key,
    required this.variant,
    required this.onComplete,
    required this.subtitle,
  });

  @override
  State<StartupLogoAnimation> createState() => _StartupLogoAnimationState();
}

class _StartupLogoAnimationState extends State<StartupLogoAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _initialFade;
  late Animation<double> _slideLeft;
  late Animation<double> _unlockFade;
  late Animation<double> _unlockSlide;
  late Animation<double> _subtitleFade;
  late Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // 0.0 -> 0.25: 414 fades in centered
    _initialFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
      ),
    );

    // 0.30 -> 0.65: 414 slides left
    _slideLeft = Tween<double>(begin: 0.0, end: -1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.30, 0.65, curve: Curves.easeInOutCubic),
      ),
    );

    // 0.45 -> 0.75: 'unlock' fades in
    _unlockFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 0.75, curve: Curves.easeIn),
      ),
    );

    // 0.45 -> 0.75: 'unlock' slides from right to center-right
    _unlockSlide = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    // 0.70 -> 0.88: Subtitle fades in
    _subtitleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.70, 0.88, curve: Curves.easeOut),
      ),
    );

    // 0.92 -> 1.0: Whole screen smooth transition out
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.92, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.variant == AppBrandVariant.iphone
        ? AppColors.iphoneBlue
        : AppColors.androidGreen;

    return GestureDetector(
      onTap: () {
        // Allow skipping
        if (_controller.value < 0.9) {
          _controller.animateTo(0.92, duration: const Duration(milliseconds: 200));
        }
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _exitFade.value.clamp(0.0, 1.0),
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main Logo Container
                    SizedBox(
                      height: 100,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // "414" Number
                          Transform.translate(
                            // Slides from center offset (0) toward left (-18px)
                            offset: Offset(_slideLeft.value * 18, 0),
                            child: Opacity(
                              opacity: _initialFade.value,
                              child: Text(
                                '414',
                                style: TextStyle(
                                  fontSize: 60,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.5,
                                  color: AppColors.textPrimary,
                                  shadows: [
                                    Shadow(
                                      color: accentColor.withValues(alpha: 0.3),
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Spacing & "unlock"
                          Opacity(
                            opacity: _unlockFade.value,
                            child: Transform.translate(
                              offset: Offset(_unlockSlide.value * 20, 0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  const SizedBox(width: 14),
                                  Text(
                                    'unlock',
                                    style: TextStyle(
                                      fontSize: 60,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: -1.0,
                                      color: accentColor,
                                      shadows: [
                                        Shadow(
                                          color: accentColor.withValues(alpha: 0.4),
                                          blurRadius: 25,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Subtitle / Variant Indicator
                    Opacity(
                      opacity: _subtitleFade.value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cardElevated,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          widget.subtitle.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.0,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
