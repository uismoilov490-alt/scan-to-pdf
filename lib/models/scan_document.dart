class ScanDocument {
  final String id;
  final String name;
  final String pdfPath;
  final int pageCount;
  final DateTime createdAt;
  final int fileSizeBytes;

  const ScanDocument({
    required this.id,
    required this.name,
    required this.pdfPath,
    required this.pageCount,
    required this.createdAt,
    required this.fileSizeBytes,
  });

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
