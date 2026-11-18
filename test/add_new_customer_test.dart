import 'package:aksab_sales/screens/rep/add_new_customer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

// Registration-screen behavior (aksabsaels):
// - location refresh keeps the previous value on any failure,
// - landmark is optional descriptive text only,
// - coordinates stay the only geo reference in the saved payload.
//
// GPS/geocoding are faked at the platform-interface level (no device).
class FakeGeolocator extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission checkResult = LocationPermission.whileInUse;
  LocationPermission requestResult = LocationPermission.whileInUse;
  Position? position;
  Object? positionError;

  static Position pos(double lat, double lng) => Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime(2026, 11, 18),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 1,
        heading: 0,
        headingAccuracy: 1,
        speed: 0,
        speedAccuracy: 0,
      );

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => checkResult;

  @override
  Future<LocationPermission> requestPermission() async => requestResult;

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    if (positionError != null) throw positionError!;
    return position!;
  }
}

class FakeGeocoding extends GeocodingPlatform {
  List<Placemark> placemarks = const [];

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) async =>
      placemarks;
}

Placemark mark(String street, String locality, String subArea) => Placemark(
      street: street,
      locality: locality,
      subAdministrativeArea: subArea,
    );

Future<void> pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: AddNewCustomerScreen()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('locationErrorMessage', () {
    test('every failure kind has a distinct non-empty message', () {
      final messages = LocationFailure.values.map(locationErrorMessage);
      expect(messages.every((m) => m.isNotEmpty), isTrue);
      expect(messages.toSet().length, LocationFailure.values.length);
    });

    test('permission and GPS messages guide the user, keep old value', () {
      expect(locationErrorMessage(LocationFailure.permissionDenied),
          contains('صلاحية'));
      expect(locationErrorMessage(LocationFailure.permissionDeniedForever),
          contains('السابقة'));
      expect(locationErrorMessage(LocationFailure.serviceDisabled),
          contains('GPS'));
      expect(locationErrorMessage(LocationFailure.unavailable),
          contains('السابقة'));
    });
  });

  group('buildRepBuyerPayload', () {
    Map<String, dynamic> base({String landmark = ''}) =>
        buildRepBuyerPayload(
          fullname: 'سوبر ماركت النور',
          ownerName: 'أحمد',
          phoneNumber: '01012345678',
          requestId: 'req-1',
          address: 'شارع 1',
          landmark: landmark,
          lat: 30.0444,
          lng: 31.2357,
        );

    test('omits landmark when empty or blank (registration allowed)', () {
      expect(base().containsKey('landmark'), isFalse);
      expect(base(landmark: '   ').containsKey('landmark'), isFalse);
    });

    test('includes trimmed landmark when written', () {
      final p = base(landmark: '  بجوار المسجد  ');
      expect(p['landmark'], 'بجوار المسجد');
    });

    test('coordinates are the only geo reference, untouched by landmark',
        () {
      final p = base(landmark: 'أمام الصيدلية');
      expect(p['location'], {'lat': 30.0444, 'lng': 31.2357});
      expect(p['location']['lat'], isNot('أمام الصيدلية'));
    });

    test('keeps the same shape as the previous request contract', () {
      final p = base();
      expect(p['country'], 'egypt');
      expect(p['requestId'], 'req-1');
      expect(p['phoneNumber'], '01012345678');
    });
  });

  group('registration screen widgets (faked GPS)', () {
    late FakeGeolocator geo;
    late FakeGeocoding coding;

    setUp(() {
      geo = FakeGeolocator()
        ..position = FakeGeolocator.pos(30.0, 31.0);
      coding = FakeGeocoding()
        ..placemarks = [mark('شارع 1', 'القاهرة', 'مصر الجديدة')];
      GeolocatorPlatform.instance = geo;
      GeocodingPlatform.instance = coding;
    });

    testWidgets('shows refresh button and optional landmark field',
        (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('علامة مميزة للموقع (اختياري)'), findsOneWidget);
      expect(find.text('بجوار مسجد كذا، أمام الصيدلية'), findsOneWidget);
      expect(find.text('عنوان الموقع (تلقائي من الـ GPS)'), findsOneWidget);
      // Initial GPS fix filled the read-only address field.
      expect(find.text('شارع 1, القاهرة, مصر الجديدة'), findsOneWidget);
    });

    testWidgets('refresh updates the location value', (tester) async {
      await pumpScreen(tester);
      expect(find.text('شارع 1, القاهرة, مصر الجديدة'), findsOneWidget);

      geo.position = FakeGeolocator.pos(31.0, 30.0);
      coding.placemarks = [mark('شارع 9', 'الجيزة', 'فيصل')];
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('شارع 9, الجيزة, فيصل'), findsOneWidget);
      expect(find.text('شارع 1, القاهرة, مصر الجديدة'), findsNothing);
    });

    testWidgets('refresh keeps other form data intact', (tester) async {
      await pumpScreen(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'اسم المحل / السوبر ماركت *'),
          'سوبر ماركت النور');

      geo.position = FakeGeolocator.pos(31.0, 30.0);
      coding.placemarks = [mark('شارع 9', 'الجيزة', 'فيصل')];
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('سوبر ماركت النور'), findsOneWidget);
      expect(find.text('شارع 9, الجيزة, فيصل'), findsOneWidget);
    });

    testWidgets('denied permission keeps the previous value', (tester) async {
      await pumpScreen(tester);
      expect(find.text('شارع 1, القاهرة, مصر الجديدة'), findsOneWidget);

      geo.checkResult = LocationPermission.denied;
      geo.requestResult = LocationPermission.denied;
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Old value preserved, guidance shown.
      expect(find.text('شارع 1, القاهرة, مصر الجديدة'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('disabled GPS keeps the previous value', (tester) async {
      await pumpScreen(tester);
      geo.serviceEnabled = false;
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('شارع 1, القاهرة, مصر الجديدة'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('failed fix keeps the previous value', (tester) async {
      await pumpScreen(tester);
      geo.positionError = Exception('no fix');
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('شارع 1, القاهرة, مصر الجديدة'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
