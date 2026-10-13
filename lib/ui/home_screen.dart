import 'package:flutter/material.dart';

import 'lobby_screen.dart';

/// Giữ tên widget cũ — luồng chính là [LobbyScreen].
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const LobbyScreen();
}
