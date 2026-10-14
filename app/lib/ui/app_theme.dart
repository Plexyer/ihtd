import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Adjacent surfaces own the paint behind transparent system bars. These roles
/// are shared by phone/drawer and desktop layouts, rather than OS-specific UI.
@immutable
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  const AppSurfaces({
    required this.canvas,
    required this.header,
    required this.sidebar,
  });
  static const light = AppSurfaces(
    canvas: Color(0xfff5f7fa),
    header: Colors.white,
    sidebar: Color(0xffeef2f7),
  );
  final Color canvas, header, sidebar;
  static AppSurfaces of(BuildContext context) =>
      Theme.of(context).extension<AppSurfaces>() ?? light;
  @override
  AppSurfaces copyWith({Color? canvas, Color? header, Color? sidebar}) =>
      AppSurfaces(
        canvas: canvas ?? this.canvas,
        header: header ?? this.header,
        sidebar: sidebar ?? this.sidebar,
      );
  @override
  AppSurfaces lerp(AppSurfaces? other, double t) => other == null
      ? this
      : AppSurfaces(
          canvas: Color.lerp(canvas, other.canvas, t)!,
          header: Color.lerp(header, other.header, t)!,
          sidebar: Color.lerp(sidebar, other.sidebar, t)!,
        );
}

SystemUiOverlayStyle surfaceOverlays({
  required Color top,
  required Color bottom,
}) {
  final topBrightness = ThemeData.estimateBrightnessForColor(top);
  final bottomBrightness = ThemeData.estimateBrightnessForColor(bottom);
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: topBrightness == Brightness.light
        ? Brightness.dark
        : Brightness.light,
    statusBarBrightness: topBrightness,
    systemNavigationBarIconBrightness: bottomBrightness == Brightness.light
        ? Brightness.dark
        : Brightness.light,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );
}

ThemeData buildIhtdTheme() {
  const ink = Color(0xff18334c);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff2763a5),
    surface: AppSurfaces.light.canvas,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: const [AppSurfaces.light],
    scaffoldBackgroundColor: AppSurfaces.light.canvas,
    fontFamily: 'Segoe UI',
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, color: ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xffdbe2eb)),
      ),
    ),
    dividerColor: const Color(0xffe1e7ef),
    visualDensity: VisualDensity.standard,
  );
}
