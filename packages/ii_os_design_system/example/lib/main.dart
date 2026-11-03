import 'package:flutter/material.dart';
import 'package:ii_os_design_system/ii_os_design_system.dart';

import 'src/gallery_shell.dart';

void main() => runApp(const GalleryApp());

/// The design system rendered against its own themes.
///
/// The gallery consumes the package exactly the way ii-os does, so anything
/// that looks wrong here is wrong in the product too. It renders both modes
/// because a palette with a mode nobody can open is a palette nobody can
/// review -- and a dark-mode mistake is invisible until someone ships it.
class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ii-os design system',
      debugShowCheckedModeBanner: false,
      theme: IiOsTheme.light(),
      darkTheme: IiOsTheme.dark(),
      themeMode: _mode,
      home: GalleryShell(
        mode: _mode,
        onModeChanged: (mode) => setState(() => _mode = mode),
      ),
    );
  }
}
