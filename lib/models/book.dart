class Book {
  final String bookId;
  final String title;
  final String? coverPath;
  final String pagesDir;
  final String vlmOutput;
  final String vlmProvider;
  final int createdAt;

  const Book({
    required this.bookId,
    required this.title,
    this.coverPath,
    required this.pagesDir,
    required this.vlmOutput,
    required this.vlmProvider,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'title': title,
        'cover_path': coverPath,
        'pages_dir': pagesDir,
        'vlm_output': vlmOutput,
        'vlm_provider': vlmProvider,
        'created_at': createdAt,
      };

  factory Book.fromMap(Map<String, dynamic> map) => Book(
        bookId: map['book_id'] as String,
        title: map['title'] as String,
        coverPath: map['cover_path'] as String?,
        pagesDir: map['pages_dir'] as String,
        vlmOutput: map['vlm_output'] as String,
        vlmProvider: map['vlm_provider'] as String,
        createdAt: map['created_at'] as int,
      );
}
