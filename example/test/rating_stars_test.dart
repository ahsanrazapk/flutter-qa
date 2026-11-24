import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qa_demo/presentation/rating_stars.dart';

void main() {
  Future<List<int>> pumpStars(
    WidgetTester tester, {
    required int rating,
  }) async {
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RatingStars(rating: rating, onChanged: changes.add),
        ),
      ),
    );
    return changes;
  }

  // Nothing inside a CustomPaint can be found, so tap where each star is drawn.
  testWidgets('tapping a star reports its number', (tester) async {
    final changes = await pumpStars(tester, rating: 0);
    final left = tester.getTopLeft(find.byType(RatingStars));

    for (final star in [1, 3, 5]) {
      await tester.tapAt(
        left + Offset(RatingStars.starSize * (star - 0.5), 20),
      );
    }

    expect(changes, [1, 3, 5]);
  });

  testWidgets('tells a screen reader its value and how it can change', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final changes = await pumpStars(tester, rating: 3);

    expect(
      tester.getSemantics(find.byType(RatingStars)),
      isSemantics(
        label: 'Rating',
        value: '3 of 5',
        increasedValue: '4 of 5',
        decreasedValue: '2 of 5',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );

    tester.semantics.increase(find.semantics.byLabel('Rating'));
    expect(changes, [4]);
    semantics.dispose();
  });

  testWidgets('cannot go above five', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpStars(tester, rating: 5);

    expect(
      tester.getSemantics(find.byType(RatingStars)),
      isSemantics(value: '5 of 5', hasIncreaseAction: false),
    );
    semantics.dispose();
  });

  testWidgets('draws three filled stars', tags: 'golden', (tester) async {
    await pumpStars(tester, rating: 3);

    await expectLater(
      find.byType(RatingStars),
      matchesGoldenFile('goldens/rating_3_of_5.png'),
    );
  });
}
