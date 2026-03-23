import 'dart:io';
import 'dart:typed_data';
import 'package:pdfx/pdfx.dart';

class PdfException implements Exception {
  final String message;
  const PdfException(this.message);
  @override
  String toString() => 'PdfException: $message';
}

class PdfService {
  /// Converts a PDF file at [path] to a list of JPEG byte arrays (one per page).
  static Future<List<Uint8List>> pdfToJpegBytes(String path) async {
    if (!File(path).existsSync()) {
      throw PdfException('File not found: $path');
    }
    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(path);
      final pageCount = document.pagesCount;
      final results = <Uint8List>[];
      for (int i = 1; i <= pageCount; i++) {
        final page = await document.getPage(i);
        try {
          final image = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: PdfPageImageFormat.jpeg,
            quality: 85,
          );
          if (image == null) {
            throw PdfException('Page $i rendered as null');
          }
          results.add(image.bytes);
        } finally {
          await page.close();
        }
      }
      return results;
    } catch (e) {
      if (e is PdfException) rethrow;
      throw PdfException('Failed to render PDF: $e');
    } finally {
      await document?.close();
    }
  }
}
