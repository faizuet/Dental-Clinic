import 'package:flutter_test/flutter_test.dart';
import 'package:nabi_dental_app/core/widgets/record_pager.dart';

void main() {
  test('pages show ten records and keep the newest page after an insert', () {
    final source = [for (var index = 0; index < 13; index++) 'Patient $index'];
    final first = RecordPage.of(source, 0);
    expect(first.from, 1);
    expect(first.to, 10);
    expect(first.total, 13);
    expect(first.items, source.take(10).toList());

    final second = RecordPage.of(source, 1);
    expect(second.from, 11);
    expect(second.to, 13);
    expect(second.items, ['Patient 10', 'Patient 11', 'Patient 12']);

    expect(settleRecordPage(page: 1, previousCount: 13, nextCount: 14), 0);
    expect(settleRecordPage(page: 1, previousCount: 13, nextCount: 11), 1);
    expect(settleRecordPage(page: 1, previousCount: 13, nextCount: 10), 0);
    expect(recordPageIndexes(0, 2), [0, 1]);
  });
}
