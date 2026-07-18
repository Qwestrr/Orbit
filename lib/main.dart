import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/app_state.dart';
import 'providers/appearance_provider.dart';
import 'screens/home_map_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/local_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await LocalNotificationService.instance.initialize();
  runApp(const CircleMapApp());
}

class CircleMapApp extends StatelessWidget {
  const CircleMapApp({super.key});

  ThemeData _buildTheme(Brightness brightness, AppearanceProvider appearance) {
    final baseTheme =
        brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    final roundedButtonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final roundedIconShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return baseTheme.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: appearance.buttonColor,
        brightness: brightness,
      ),
      brightness: brightness,
      textTheme: baseTheme.textTheme.apply(
        bodyColor: appearance.textColor,
        displayColor: appearance.textColor,
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: const WidgetStatePropertyAll<Icon?>(null),
        trackOutlineColor:
            const WidgetStatePropertyAll<Color>(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return brightness == Brightness.dark
              ? const Color(0xFFF5F5F5)
              : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return appearance.buttonColor;
          }
          return brightness == Brightness.dark
              ? const Color(0xFF3A3A3C)
              : const Color(0xFFD1D1D6);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: outlineBorder,
        enabledBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: baseTheme.dividerColor),
        ),
        focusedBorder: outlineBorder.copyWith(
          borderSide:
            BorderSide(color: appearance.buttonColor, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(roundedButtonShape),
          minimumSize: const WidgetStatePropertyAll<Size>(Size(44, 44)),
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(roundedButtonShape),
          minimumSize: const WidgetStatePropertyAll<Size>(Size(44, 44)),
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(roundedButtonShape),
          minimumSize: const WidgetStatePropertyAll<Size>(Size(44, 44)),
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(roundedButtonShape),
          minimumSize: const WidgetStatePropertyAll<Size>(Size(44, 44)),
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(roundedIconShape),
          minimumSize: const WidgetStatePropertyAll<Size>(Size(40, 40)),
          padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.all(8)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: roundedIconShape,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(
            create: (_) => AppearanceProvider()..loadFromPrefs()),
      ],
      child: Consumer<AppearanceProvider>(
        builder: (context, appearance, _) {
          return MaterialApp(
            title: 'Circle Map',
            debugShowCheckedModeBanner: false,
            themeMode: appearance.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            theme: _buildTheme(Brightness.light, appearance),
            darkTheme: _buildTheme(Brightness.dark, appearance),
            home: const _AuthGate(),
          );
        },
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return StreamBuilder(
      stream: appState.auth.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user == null) {
          return const OnboardingScreen();
        }

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await appState.initializeLocationAccess(context);
          await appState.initForUser(user.uid);
        });
        return const HomeMapScreen();
      },
    );
  }
}
