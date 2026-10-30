import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:airdrop_qr/l10n/app_localizations.dart';
import 'package:airdrop_qr/presentation/pages/home_page.dart';
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
  const ZeroSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZeroSync',
      debugShowCheckedModeBanner: false,
      theme: ZeroSyncTheme.oledBlackTheme,
      darkTheme: ZeroSyncTheme.oledBlackTheme,
      themeMode: ThemeMode.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ZeroSyncHomePage(),
    );
  }
}
