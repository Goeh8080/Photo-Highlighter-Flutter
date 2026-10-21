import 'package:flutter_test/flutter_test.dart';
import 'package:photo_merger_highlighter/services/pdf_service.dart';

void main() {
  test('parsePageInput handles lists and ranges like the HTML', () {
    expect(PdfService.parsePageInput('1, 5, 9', 10), [1, 5, 9]);
    expect(PdfService.parsePageInput('3-1, 2, 40', 10), [1, 2, 3]);
    expect(PdfService.parsePageInput('x', 10), isEmpty);
  });
}
