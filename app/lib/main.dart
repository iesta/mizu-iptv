import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'platform/app_dirs.dart';
import 'state/app_state.dart';
import 'theme/omarchy_theme.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/tv_focus.dart';
import 'mizu_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppDirs.init();
  MizuConfig.init();
  await Supabase.initialize(
    url: MizuConfig.backendUrl,
    publishableKey: MizuConfig.publishableKey,
  );
  runApp(MizuApp(state: AppState()));
}

class MizuApp extends StatefulWidget {
  const MizuApp({super.key, required this.state});

  final AppState state;

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
        return MaterialApp(
          title: 'Mizu IPTV',
          debugShowCheckedModeBanner: false,
          theme: _themes.theme,
          home: TvShortcuts(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: widget.state.isSignedIn
                  ? HomePage(key: const ValueKey('home'), state: widget.state)
                  : LoginPage(key: const ValueKey('login'), state: widget.state),
            ),
          ),
        );
      },
    );
  }
}
