import 'package:flutter/material.dart';


void main() {
  runApp(const SnackbarAlternativesApp());
}

class SnackbarAlternativesApp extends StatelessWidget {
  const SnackbarAlternativesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snackbar Alternatives Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const SnackbarDemoPage(),
    );
  }
}

class SnackbarDemoPage extends StatelessWidget {
  const SnackbarDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Snackbar Alternatives")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("This is a SnackBar")),
                );
              },
              child: const Text("Show SnackBar"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Dialog Example"),
                    content: const Text("This is an AlertDialog message."),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("OK"),
                      ),
                    ],
                  ),
                );
              },
              child: const Text("Show AlertDialog"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => Container(
                    padding: const EdgeInsets.all(16),
                    height: 150,
                    child: const Center(
                      child: Text("This is a Bottom Sheet message!"),
                    ),
                  ),
                );
              },
              child: const Text("Show BottomSheet"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showMaterialBanner(
                  MaterialBanner(
                    content: const Text("This is a MaterialBanner"),
                    leading: const Icon(Icons.info_outline),
                    actions: [
                      TextButton(
                        onPressed: () => ScaffoldMessenger.of(context)
                            .hideCurrentMaterialBanner(),
                        child: const Text("DISMISS"),
                      ),
                    ],
                  ),
                );
              },
              child: const Text("Show MaterialBanner"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                _showCustomOverlay(context);
              },
              child: const Text("Show Custom Overlay Message"),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomOverlay(BuildContext context) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 100,
        left: MediaQuery.of(context).size.width * 0.1,
        right: MediaQuery.of(context).size.width * 0.1,
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(12),
          color: Colors.black.withValues(alpha: 0.8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                "This is a Custom Overlay Message!",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(milliseconds: 800), () {
      overlayEntry.remove();
    });
  }
}
