import 'package:flutter/material.dart';
import 'package:filebrowser_mobile/l10n/app_localizations.dart';

/// The English [AppLocalizations], for unit tests that call display-string
/// helpers directly (no widget tree needed).
final AppLocalizations l10nEn = lookupAppLocalizations(const Locale('en'));

/// Wraps [child] in a [MaterialApp] configured with the app's localization
/// delegates, mirroring what `FileBrowserApp` provides in production. Widget
/// tests that pump a screen directly should use this instead of a bare
/// [MaterialApp] so `AppLocalizations.of(context)` resolves.
Widget l10nWrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}
