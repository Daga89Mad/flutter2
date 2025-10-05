// lib/views/loginBody.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:plantillalogin/core/firebaseCrudService.dart';
import 'package:plantillalogin/views/menu.dart';
import 'package:plantillalogin/views/registerScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginBody extends StatefulWidget {
  const LoginBody({super.key});

  @override
  State<LoginBody> createState() => _LoginBodyState();
}

class _LoginBodyState extends State<LoginBody> {
  // Servicio de autenticación
  final FirebaseCrudService _authService = FirebaseCrudService();

  // Controladores y almacenamiento seguro
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Estado interno
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _remember = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('remember_me') ?? false;
    if (!remember) return;

    final savedEmail = prefs.getString('saved_email');
    final savedPass = await _secureStorage.read(key: 'saved_pass');

    if (savedEmail != null) _emailCtrl.text = savedEmail;
    if (savedPass != null) _passCtrl.text = savedPass;

    setState(() => _remember = true);
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Intentar iniciar sesión (no registrar)
      // Asumo que tu FirebaseCrudService tiene un método signInWithEmail,
      // si no, puedes usar directamente FirebaseAuth.instance.signInWithEmailAndPassword
      await _authService.signInWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      final prefs = await SharedPreferences.getInstance();

      if (_remember) {
        await prefs.setBool('remember_me', true);
        await prefs.setString('saved_email', _emailCtrl.text.trim());
        await _secureStorage.write(key: 'saved_pass', value: _passCtrl.text);
      } else {
        await prefs.remove('remember_me');
        await prefs.remove('saved_email');
        await _secureStorage.delete(key: 'saved_pass');
      }

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MenuScreen()));
    } on FirebaseAuthException catch (e) {
      // Manejo de errores más granular
      switch (e.code) {
        case 'user-not-found':
          setState(
            () => _errorMessage = 'No existe una cuenta con ese correo.',
          );
          break;
        case 'wrong-password':
          setState(() => _errorMessage = 'Contraseña incorrecta.');
          break;
        case 'user-disabled':
          setState(() => _errorMessage = 'Cuenta deshabilitada.');
          break;
        case 'invalid-email':
          setState(() => _errorMessage = 'Correo inválido.');
          break;
        case 'email-already-in-use':
          setState(
            () => _errorMessage =
                'El correo ya está en uso. ¿Quieres registrarte con otro o recuperar la contraseña?',
          );
          break;
        default:
          setState(
            () => _errorMessage = e.message ?? 'Error de autenticación.',
          );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error inesperado: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _goToRegister() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Imagen superior (asegúrate de declarar el asset en pubspec.yaml)
                Image.asset(
                  'assets/images/logo.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),

                const SizedBox(height: 32),

                // Campo de correo electrónico
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email),
                  ),
                ),

                const SizedBox(height: 16),

                // Campo de contraseña
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Checkbox “Recuérdame”
                CheckboxListTile(
                  title: const Text('Recuérdame'),
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                // Mensaje de error
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],

                const SizedBox(height: 16),

                // Botón de inicio de sesión
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _signIn,
                        child: const Text('Iniciar sesión'),
                      ),

                const SizedBox(height: 12),

                // Enlace a registro
                TextButton(
                  onPressed: _goToRegister,
                  child: const Text('¿Nuevo usuario? Regístrate'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
