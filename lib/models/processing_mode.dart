enum ProcessingMode {
  textHeavy,
  pictureBook;

  String toApiValue() => switch (this) {
        ProcessingMode.textHeavy => 'text_heavy',
        ProcessingMode.pictureBook => 'picture_book',
      };
}
