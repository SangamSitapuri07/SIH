import 'package:flutter/material.dart';

import 'api/orca_client.dart';
import 'screens/chat_screen.dart';
import 'theme.dart';

void main() {
  runApp(const OrcaApp());
}

class OrcaApp extends StatelessWidget {
  const OrcaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // For an Android emulator the host machine is reachable at 10.0.2.2.
    // For a real device, override the URL with your laptop's LAN IP, e.g.
    //   const baseUrl = 'http://192.168.1.10:8000';
    const baseUrl = 'http://10.0.2.2:8000';
    final client = OrcaClient(baseUrl: Uri.parse(baseUrl));

    return MaterialApp(
      title: 'ORCA Marine Intelligence',
      theme: buildOrcaTheme(),
      debugShowCheckedModeBanner: false,
      home: ChatScreen(client: client),
    );
  }
}
