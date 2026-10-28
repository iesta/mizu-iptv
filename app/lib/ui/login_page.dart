import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'settings_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.state});

  final AppState state;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _emailKey = GlobalKey();
  final _passwordKey = GlobalKey();
  bool _busy = false;
  bool _signUp = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(() => _revealField(_emailFocus, _emailKey));
    _passwordFocus.addListener(
        () => _revealField(_passwordFocus, _passwordKey));
  }

  /// Sur TV/Android, le clavier s'affiche en surimpression (pas de
  /// `viewInsets`) et masque le champ : on le fait défiler en haut d'écran.
  void _revealField(FocusNode node, GlobalKey key) {
    if (!node.hasFocus) return;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      final ctx = key.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.05,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Email et mot de passe requis.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signUp) {
        await widget.state.signUp(_email.text, _password.text);
        if (mounted && !widget.state.isSignedIn) {
          setState(() => _error =
              'Compte créé : vérifie ta boîte mail pour confirmer, puis connecte-toi.');
        }
      } else {
        await widget.state.signIn(_email.text, _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _readable(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _readable(Object e) {
    final raw = e.toString();
    if (raw.contains('Invalid login credentials')) {
      return 'Email ou mot de passe incorrect.';
    }
    if (raw.contains('Email not confirmed')) {
      return 'Email non confirmé : valide le lien reçu par mail.';
    }
    return raw.replaceFirst('AuthException(message: ', '').replaceFirst(RegExp(r',$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Préférences (serveur, clé)',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsPage(state: widget.state),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset('assets/logo.png', width: 96, height: 96),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Mizu IPTV',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  _signUp ? 'Créer un compte Zen' : 'Connexion au compte Zen',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                KeyedSubtree(
                  key: _emailKey,
                  child: TextField(
                    controller: _email,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.alternate_email),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _passwordKey,
                  child: TextField(
                    controller: _password,
                    focusNode: _passwordFocus,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_signUp ? 'Créer le compte' : 'Se connecter'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _signUp = !_signUp;
                            _error = null;
                          }),
                  child: Text(_signUp
                      ? 'J\'ai déjà un compte'
                      : 'Créer un compte Zen'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Client non officiel. Utilise ton propre compte et '
                  'tes propres sources.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
