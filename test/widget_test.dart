import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web entrypoint loads the Google Maps JavaScript API', () {
    final indexFile = File('web/index.html');

    expect(indexFile.existsSync(), isTrue);

    final html = indexFile.readAsStringSync();
    expect(html, contains('https://maps.googleapis.com/maps/api/js'));
    expect(html, contains('AIzaSyC4HI8h7tYM5FCNjZpASdtciK4JhetMGxs'));
  });
}
