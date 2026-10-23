import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mizu_config.dart';
import 'platform/app_dirs.dart';
import 'state/app_state.dart';
import 'theme/omarchy_theme.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/settings_page.dart';
import 'ui/tv_focus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppDirs.init();
  MizuConfig.init();

  // Sans backend configuré, on n'initialise pas Supabase : l'app affiche
  // l'écran de configuration au premier lancement.
  if (MizuConfig.isConfigured) {
    await Supabase.initialize(
      url: MizuConfig.backendUrl,
      publishableKey: MizuConfig.publishableKey,
    );
  }

  runApp(MizuApp(state: MizuConfig.isConfigured ? AppState() : null));
}

class MizuApp extends StatefulWidget {
  const MizuApp({super.key, required this.state});

  /// `null` tant que le backend n'est pas configuré.
  final AppState? state;

  @override
  State<MizuApp> createState() => _MizuAppState();
}

class _MizuAppState extends State<MizuApp> {
  final ThemeController _themes = ThemeController();

  @override
  void dispose() {
    _themes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.state, _themes]),
      builder: (context, _) {
        final state = widget.state;
        final Widget home;
        if (state == null) {
          home = const SettingsPage(state: null, firstRun: true);
        } else {
          home = TvShortcuts(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: state.isSignedIn
                  ? HomePage(key: const ValueKey('home'), state: state)
                  : LoginPage(key: const ValueKey('login'), state: state),
            ),
          );
        }
        return MaterialApp(
          title: 'Mizu IPTV',
          debugShowCheckedModeBanner: false,
          theme: _themes.theme,
          home: home,
        );
      },
    );
  }
}
