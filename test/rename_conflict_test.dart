import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/veri_fin_controller.dart';

import 'support/test_harness.dart';

void main() {
  test('renaming a category to a sibling name is rejected', () async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    controller
      ..addCategory(type: EntryType.expense, label: 'A', iconCode: 'wallet')
      ..addCategory(type: EntryType.expense, label: 'B', iconCode: 'wallet');
    final categoryA = controller.categories.singleWhere((c) => c.label == 'A');
    final categoryB = controller.categories.singleWhere((c) => c.label == 'B');

    expect(
      await controller.renameCategory(categoryB.id, 'A'),
      RenameResult.duplicate,
    );
    expect(
      controller.categories.where((category) => category.label == 'A'),
      hasLength(1),
    );
    expect(
      controller.categories.where((category) => category.label == 'B'),
      hasLength(1),
    );
    expect(
      controller.categories.singleWhere((c) => c.id == categoryA.id).label,
      'A',
    );
    expect(
      controller.categories.singleWhere((c) => c.id == categoryB.id).label,
      'B',
    );
  });

  test('renaming a tag to an existing tag is rejected', () async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    final first = controller.addTag('A')!;
    final second = controller.addTag('B')!;

    expect(await controller.renameTag(second, 'A'), RenameResult.duplicate);
    expect(controller.tagById(first)!.label, 'A');
    expect(controller.tagById(second)!.label, 'B');
  });
}
