import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets/ai_soi_bcr_logo.dart';

/// Màn khởi động: nền [background-auth.png] + logo chữ A.I SOI BCR.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final logoSize = (h * 0.068).clamp(42.0, 58.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/background-auth.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: h * 0.08),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Center(
                      child: AiSoiBcrLogo(
                        fontSize: logoSize,
                        maxWidth: MediaQuery.sizeOf(context).width - 40,
                        letterSpacing: 3.6,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
