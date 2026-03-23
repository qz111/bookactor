import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pdfToJpegBytes returns non-empty list for a valid PDF', () async {
    final file = File('test/assets/sample.pdf');
    // Skip if the test asset was not created
    if (!file.existsSync()) {
      markTestSkipped('test/assets/sample.pdf not found — skipping');
      return;
    }
    try {
      final bytes = await PdfService.pdfToJpegBytes(file.path);
      expect(bytes, isNotEmpty);
      expect(bytes.first, isNotEmpty);
    } on PdfException catch (e) {
      // pdfx requires a native renderer; skip gracefully in headless test mode
      if (e.message.contains('MissingPluginException')) {
        markTestSkipped('pdfx native renderer not available in test environment — skipping');
        return;
      }
      rethrow;
    } on MissingPluginException {
      markTestSkipped('pdfx native renderer not available in test environment — skipping');
    }
  });

  test('pdfToJpegBytes throws PdfException for non-existent file', () async {
    await expectLater(
      () => PdfService.pdfToJpegBytes('/no/such/file.pdf'),
      throwsA(isA<PdfException>()),
    );
  });
}
