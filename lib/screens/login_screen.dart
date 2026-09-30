import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'library_screen.dart';

/// Écran de connexion : adresse du serveur, identifiant, mot de passe.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _store = SessionStore();

  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pré-remplit l'adresse utilisée la dernière fois
    _store.lastServerUrl().then((url) {
      if (url != null && mounted) _serverController.text = url;
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final serverUrl = normalizeServerUrl(_serverController.text);
      final api = JellyfinApi(
        serverUrl: serverUrl,
        deviceId: await _store.deviceId(),
      );

      // 1. Un serveur Jellyfin répond-il à cette adresse ?
      try {
        await api.getServerName();
      } on JellyfinException catch (e) {
        throw JellyfinException('Aucun serveur Jellyfin trouvé : ${e.message}');
      }

      // 2. Connexion : on récupère le jeton
      final session = await api.authenticateByName(
        _userController.text.trim(),
        _passwordController.text,
      );
      api.token = session.accessToken;

      // 3. On range le jeton dans le coffre-fort (jamais le mot de passe)
      await _store.save(session);
      _passwordController.clear();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LibraryScreen(api: api, session: session),
        ),
      );
    } on FormatException {
      setState(() => _error = 'Adresse du serveur invalide.');
    } on JellyfinException catch (e) {
      setState(() {
        _error = e.isUnauthorized
            ? 'Identifiant ou mot de passe incorrect.'
            : e.message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlowBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Amplyfin',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(fontSize: 44),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Connexion à ton serveur Jellyfin',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: AppColors.grey),
                      ),
                      const SizedBox(height: 40),
                      TextFormField(
                        controller: _serverController,
                        decoration: const InputDecoration(
                          labelText: 'Adresse du serveur',
                          hintText: 'http://192.168.1.10:8096',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Indique l\'adresse du serveur'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _userController,
                        decoration: const InputDecoration(
                          labelText: 'Identifiant',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Indique ton identifiant'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      // Le mot de passe peut être vide sur Jellyfin : pas de validation
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _hidePassword = !_hidePassword),
                          ),
                        ),
                        obscureText: _hidePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _loading ? null : _login(),
                      ),
                      const SizedBox(height: 24),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      FilledButton(
                        onPressed: _loading ? null : _login,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 56),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text('Se connecter'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
