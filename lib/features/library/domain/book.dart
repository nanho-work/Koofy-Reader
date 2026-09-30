enum BookSourceType { asset, localFile }

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.sourceType,
    this.assetPath,
    this.localPath,
    this.coverPath,
    this.importSourcePath,
    this.sourceHash,
    this.originalFileName,
  });

  factory Book.asset({
    required String id,
    required String title,
    required String author,
    required String description,
    required String assetPath,
  }) {
    return Book(
      id: id,
      title: title,
      author: author,
      description: description,
      sourceType: BookSourceType.asset,
      assetPath: assetPath,
    );
  }

  factory Book.localFile({
    required String id,
    required String title,
    required String author,
    required String description,
    required String localPath,
    String? coverPath,
    String? importSourcePath,
    String? sourceHash,
    String? originalFileName,
  }) {
    return Book(
      id: id,
      title: title,
      author: author,
      description: description,
      sourceType: BookSourceType.localFile,
      localPath: localPath,
      coverPath: coverPath,
      importSourcePath: importSourcePath,
      sourceHash: sourceHash,
      originalFileName: originalFileName,
    );
  }

  final String id;
  final String title;
  final String author;
  final String description;
  final BookSourceType sourceType;
  final String? assetPath;
  final String? localPath;
  final String? coverPath;

  /// Original picker identity for duplicate selection; never used to read a book.
  final String? importSourcePath;
  final String? sourceHash;
  final String? originalFileName;

  /// Keep a filename, never a title or an app-owned `source.txt` fallback.
  String? get matchingFileName =>
      originalFileName ?? importSourcePath?.split(RegExp(r'[\\/]')).last;

  bool get isLocalFile => sourceType == BookSourceType.localFile;

  Book withCoverPath(String? path) => Book(
    id: id,
    title: title,
    author: author,
    description: description,
    sourceType: sourceType,
    assetPath: assetPath,
    localPath: localPath,
    coverPath: path,
    importSourcePath: importSourcePath,
    sourceHash: sourceHash,
    originalFileName: originalFileName,
  );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'description': description,
      'sourceType': sourceType.name,
      'assetPath': assetPath,
      'localPath': localPath,
      'coverPath': coverPath,
      'importSourcePath': importSourcePath,
      'sourceHash': sourceHash,
      'originalFileName': matchingFileName,
    };
  }

  static Book? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final author = json['author'];
    final description = json['description'];
    final sourceTypeRaw = json['sourceType'];
    if (id is! String ||
        title is! String ||
        author is! String ||
        description is! String ||
        sourceTypeRaw is! String) {
      return null;
    }
    final sourceType = BookSourceType.values.firstWhere(
      (type) => type.name == sourceTypeRaw,
      orElse: () => BookSourceType.asset,
    );
    final assetPath = json['assetPath'];
    final localPath = json['localPath'];
    return Book(
      id: id,
      title: title,
      author: author,
      description: description,
      sourceType: sourceType,
      originalFileName: json['originalFileName'] is String
          ? json['originalFileName'] as String
          : null,
      assetPath: assetPath is String ? assetPath : null,
      localPath: localPath is String ? localPath : null,
      sourceHash: json['sourceHash'] is String
          ? json['sourceHash'] as String
          : null,
      coverPath: json['coverPath'] is String
          ? json['coverPath'] as String
          : null,
      importSourcePath: json['importSourcePath'] is String
          ? json['importSourcePath'] as String
          : null,
    );
  }
}
