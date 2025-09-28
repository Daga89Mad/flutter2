// lib/views/menu_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:plantillalogin/views/ClassificationScreen.dart';
import 'package:plantillalogin/views/LoginBody.dart';
import 'package:plantillalogin/views/ResultsScreen.dart';
import 'package:plantillalogin/views/createGroupScreen.dart';
import 'package:plantillalogin/views/gameGroupsScreen.dart';
import 'package:plantillalogin/views/searchGroupsScreen.dart';
import 'package:plantillalogin/views/settingsScreen.dart';
import 'package:plantillalogin/views/viewResultsScreen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({Key? key}) : super(key: key);

  Future<void> _signOutAndGoToLogin(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    // Reemplaza LoginScreen por tu widget de autenticación
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginBody()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menú Principal')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.1,
          children: [
            _MenuButton(
              icon: Icons.upload_file,
              label: 'Cargar resultados',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ResultsScreen()),
                );
              },
            ),
            _MenuButton(
              icon: Icons.leaderboard,
              label: 'Clasificación',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ClassificationScreen(),
                  ),
                );
              },
            ),
            _MenuButton(
              icon: Icons.visibility,
              label: 'Ver resultados',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ViewResultsScreen()),
                );
              },
            ),
            _MenuButton(
              icon: Icons.group,
              label: 'Grupos de juego',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GameGroupsScreen()),
                );
              },
            ),
            _MenuButton(
              icon: Icons.add_circle,
              label: 'Crear grupo',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                );
              },
            ),
            _MenuButton(
              icon: Icons.search,
              label: 'Buscar grupo',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const JoinGroupScreen()),
                );
              },
            ),
            _MenuButton(
              icon: Icons.settings,
              label: 'Ajustes',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            _MenuButton(
              icon: Icons.logout,
              label: 'Logout',
              onTap: () => _signOutAndGoToLogin(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
