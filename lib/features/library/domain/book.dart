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
  }) {
    return Book(
      id: id,
      title: title,
      author: author,
      description: description,
      sourceType: BookSourceType.localFile,
      localPath: localPath,
    );
  }

  final String id;
  final String title;
  final String author;
  final String description;
  final BookSourceType sourceType;
  final String? assetPath;
  final String? localPath;

  bool get isLocalFile => sourceType == BookSourceType.localFile;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'description': description,
      'sourceType': sourceType.name,
      'assetPath': assetPath,
      'localPath': localPath,
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
      assetPath: assetPath is String ? assetPath : null,
      localPath: localPath is String ? localPath : null,
    );
  }
}
