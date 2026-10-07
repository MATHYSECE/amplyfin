import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../services/profile_switch.dart';
import '../services/session_store.dart';
import '../services/device_capabilities.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import '../widgets/tv_focus.dart';
import 'main_screen.dart';
import 'profiles_screen.dart';

/// Écran de connexion : adresse du serveur, identifiant, mot de passe.
/// Ouvert depuis « Qui regarde ? » (« Ajouter un profil »), un bouton
/// ramène en arrière.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.userName, this.message});

  /// Identifiant pré-rempli (ex. connexion expirée d'un profil).
  final String? userName;

  /// Explication affichée sous le titre (ex. « La connexion a expiré »).
  final String? message;

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
    _userController.text = widget.userName ?? '';
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

      // L'appli passe sur ce compte (nouveau profil, ou le même reconnecté)
      beginProfile(api, session.userId, online: true);
      if (!mounted) return;
      showOnly(context, MainScreen(api: api, session: session));
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
    // Ouvert depuis « Qui regarde ? » : bouton retour en haut à gauche
    final canGoBack = Navigator.of(context).canPop();
    return Scaffold(
      body: GlowBackground(
        child: SafeArea(
          child: Stack(
            children: [
              _buildForm(context),
              if (canGoBack)
                Positioned(
                  top: 12,
                  left: 16,
                  child: GlassCircleButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Retour',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            // Télé : haut et bas passent d'un champ à l'autre
            child: TvTextFieldNavigation(
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
                    widget.message ?? 'Connexion à ton serveur Jellyfin',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: AppColors.grey),
                  ),
                  const SizedBox(height: 40),
                  // Télé : sélectionné à l'arrivée, clavier fermé
                  TvTextField(
                    autofocus: true,
                    builder: (focusNode) => TextFormField(
                      focusNode: focusNode,
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
                  ),
                  const SizedBox(height: 16),
                  TvTextField(
                    builder: (focusNode) => TextFormField(
                      focusNode: focusNode,
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
                  ),
                  const SizedBox(height: 16),
                  // Le mot de passe peut être vide sur Jellyfin : pas de validation
                  TvTextField(
                    builder: (focusNode) => TextFormField(
                      focusNode: focusNode,
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        // Télé : pas de bouton « œil » (rien à toucher)
                        suffixIcon: DeviceCapabilities.isTv
                            ? null
                            : IconButton(
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                              ),
                      ),
                      obscureText: _hidePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _login(),
                    ),
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
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Se connecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
