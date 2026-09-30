class Release {
  final String tagName;
  final String? name;
  final String? body;
  final DateTime? publishedAt;
  final bool prerelease;
  final bool draft;
  final List<ReleaseAsset> assets;

  Release({
    required this.tagName,
    this.name,
    this.body,
    this.publishedAt,
    required this.prerelease,
    required this.draft,
    required this.assets,
  });

  Release copyWith({
    String? tagName,
    String? name,
    String? body,
    DateTime? publishedAt,
    bool? prerelease,
    bool? draft,
    List<ReleaseAsset>? assets,
  }) {
    return Release(
      tagName: tagName ?? this.tagName,
      name: name ?? this.name,
      body: body ?? this.body,
      publishedAt: publishedAt ?? this.publishedAt,
      prerelease: prerelease ?? this.prerelease,
      draft: draft ?? this.draft,
      assets: assets ?? this.assets,
    );
  }

  factory Release.fromJson(Map<String, dynamic> json) {
    final rawPublishedAt = json['published_at'];
    final rawAssets = json['assets'];
    return Release(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String?,
      body: json['body'] as String?,
      publishedAt: rawPublishedAt is String
          ? (DateTime.tryParse(rawPublishedAt) ??
              DateTime.fromMillisecondsSinceEpoch(0))
          : null,
      prerelease: json['prerelease'] as bool? ?? false,
      draft: json['draft'] as bool? ?? false,
      assets: rawAssets is List
          ? rawAssets
              .whereType<Map<String, dynamic>>()
              .map(ReleaseAsset.fromJson)
              .toList()
          : <ReleaseAsset>[],
    );
  }
}

class ReleaseAsset {
  final String name;
  final String browserDownloadUrl;
  final String contentType;
  final int size;

  ReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.contentType,
    required this.size,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: json['name'] as String? ?? '',
      browserDownloadUrl: json['browser_download_url'] as String? ?? '',
      contentType: json['content_type'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}
