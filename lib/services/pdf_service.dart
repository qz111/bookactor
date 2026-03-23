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
    try {
      final document = await PdfDocument.openFile(path);
      final pageCount = document.pagesCount;
      final results = <Uint8List>[];
      for (int i = 1; i <= pageCount; i++) {
        final page = await document.getPage(i);
        final image = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
          quality: 85,
        );
        results.add(image!.bytes);
        await page.close();
      }
      await document.close();
      return results;
    } catch (e) {
      if (e is PdfException) rethrow;
      throw PdfException('Failed to render PDF: $e');
    }
  }
}
