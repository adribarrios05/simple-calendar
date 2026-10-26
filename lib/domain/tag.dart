/// Local catalogue metadata. Membership lives in each Task snapshot.
class Tag {
  final String id, name;
  final int color;
  final bool archived;
  const Tag({
    required this.id,
    required this.name,
    required this.color,
    this.archived = false,
  });

  bool get predefined => defaultTags.any((t) => t.id == id);
  String get normalizedName => name.trim().toLowerCase();
  void validate() {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id) ||
        name.trim().isEmpty ||
        name != name.trim() ||
        name.length > 40 ||
        color < 0xff000000 ||
        color > 0xffffffff ||
        (predefined && archived)) {
      throw const FormatException(
        'Invalid tag: use a name of 1 to 40 characters and an opaque color.',
      );
    }
  }

  Tag copy({String? name, int? color, bool? archived}) => Tag(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    archived: archived ?? this.archived,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'archived': archived,
  };
  factory Tag.fromJson(Map<String, dynamic> j) {
    final tag = Tag(
      id: j['id'] as String,
      name: j['name'] as String,
      color: j['color'] as int,
      archived: j['archived'] as bool,
    );
    tag.validate();
    return tag;
  }
}

const tagPalette = <int>[
  0xff9bafe5,
  0xffb6a2db,
  0xff91c7b1,
  0xffe2b49a,
  0xffd4c68d,
  0xff91c5cd,
  0xffd5a6c8,
  0xffb0b8c3,
];
const defaultTags = <Tag>[
  Tag(id: 'tag-trabajo', name: 'Trabajo', color: 0xff9bafe5),
  Tag(id: 'tag-estudio', name: 'Estudio', color: 0xffb6a2db),
  Tag(id: 'tag-entrenamiento', name: 'Entrenamiento', color: 0xff91c7b1),
  Tag(id: 'tag-personal', name: 'Personal', color: 0xffe2b49a),
  Tag(id: 'tag-hogar', name: 'Hogar', color: 0xffd4c68d),
  Tag(id: 'tag-salud', name: 'Salud', color: 0xff91c5cd),
  Tag(id: 'tag-ocio', name: 'Ocio', color: 0xffd5a6c8),
  Tag(id: 'tag-otros', name: 'Otros', color: 0xffb0b8c3),
];

/// Null = all; empty string = untagged; otherwise one stable catalogue ID.
bool matchesTag(List<String> ids, String? filter) =>
    filter == null || (filter.isEmpty ? ids.isEmpty : ids.contains(filter));
