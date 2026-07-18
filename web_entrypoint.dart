import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:circle_map/main.dart' as app;

void main() async {
  // Initialize Flutter for web
  setUrlStrategy(PathUrlStrategy());
  
  // Configure web-specific settings
  _configureWeb();
  
  // Run the app
  app.main();
}

/// Configures web-specific settings for the application
void _configureWeb() {
  // You can add additional web-specific initialization here:
  // - Request persistent storage
  // - Configure service workers
  // - Set up web-specific handlers
}
