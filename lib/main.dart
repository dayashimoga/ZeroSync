import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:airdrop_qr/l10n/app_localizations.dart';
import 'package:airdrop_qr/presentation/pages/unified_platform_shell.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ZeroSyncApp());
}

/// Root widget for the ZeroSync air-gapped application.
class ZeroSyncApp extends StatelessWidget {
  final Widget? home;
  final ThemeData? theme;

  const ZeroSyncApp({super.key, this.home, this.theme});

  @override
  Widget build(BuildContext context) {
    final effectiveTheme = theme ?? ZeroSyncTheme.oledBlackTheme;
    return MaterialApp(
      title: 'ZeroSync',
      debugShowCheckedModeBanner: false,
      theme: effectiveTheme,
      darkTheme: effectiveTheme,
      themeMode: ThemeMode.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home ?? const UnifiedPlatformShell(),
    );
  }
}
