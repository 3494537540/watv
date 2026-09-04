import 'package:flutter/material.dart';

import '../pages/main_shell.dart';
import '../state/cms_auth_controller.dart';
import 'app_onboarding.dart';
import 'brand_splash.dart';

/// 启动入口：就绪后一律进首页（登录与否均可浏览）
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CmsAuthController.instance,
      builder: (context, _) {
        final auth = CmsAuthController.instance;
        if (!auth.isReady) {
          return const Scaffold(body: BrandSplashView());
        }
        return const AppOnboardingGate(child: MainShell());
      },
    );
  }
}
