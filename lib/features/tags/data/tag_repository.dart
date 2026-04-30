import 'package:drift/drift.dart' as drift;

import '../../../infrastructure/database/app_database.dart';

const String kTagTargetDocument = 'document';
const String kTagTargetSidecarNote = 'sidecarNote';
const String kTagTargetDocumentNote = 'documentNote';
const String kTagTargetHighlight = 'highlight';
const String kTagTargetTodo = 'todo';

const String kTagScopeDocument = 'document';
const String kTagScopeKnowledge = 'knowledge';
const String kTagScopeBoth = 'both';

const int kDefaultTagColorValue = 0xFF64748B;
const String kDefaultTagIconKey = 'tag';
const String kDefaultKnowledgeTagIconKey = 'idea';

class AppTag {
  final int id;
  final String name;
  final String? description;
  final int colorValue;
  final String iconKey;
  final int? parentTagId;
  final int sortOrder;
  final String scope;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;

  const AppTag({
    required this.id,
    required this.name,
    required this.description,
    required this.colorValue,
    required this.iconKey,
    required this.parentTagId,
    required this.sortOrder,
    required this.scope,
    required this.createdAt,
    required this.updatedAt,
    required this.archivedAt,
  });

  bool get isArchived => archivedAt != null;
}

class TagAssignment {
  final String id;
  final int tagId;
  final String targetType;
  final String targetId;
  final String? documentId;
  final DateTime createdAt;

  const TagAssignment({
    required this.id,
    required this.tagId,
    required this.targetType,
    required this.targetId,
    required this.documentId,
    required this.createdAt,
  });
}

class TagUsageSummary {
  final int tagId;
  final int totalCount;
  final int documentCount;
  final int noteCount;
  final int todoCount;
  final int highlightCount;

  const TagUsageSummary({
    required this.tagId,
    required this.totalCount,
    required this.documentCount,
    required this.noteCount,
    required this.todoCount,
    required this.highlightCount,
  });

  static const empty = TagUsageSummary(
    tagId: -1,
    totalCount: 0,
    documentCount: 0,
    noteCount: 0,
    todoCount: 0,
    highlightCount: 0,
  );
}

class TagRepository {
  final AppDatabase database;

  bool _schemaReady = false;

  TagRepository({required this.database});

  Future<void> ensureSchema() async {
    if (_schemaReady) return;

    await database.customStatement('''
CREATE TABLE IF NOT EXISTS tag_assignments (
  id TEXT NOT NULL PRIMARY KEY,
  tag_id INTEGER NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  document_id TEXT,
  created_at INTEGER NOT NULL,
  UNIQUE(tag_id, target_type, target_id)
)
''');

    final tagColumns = await _tableColumns('tags');

    if (!tagColumns.contains('description')) {
      await database.customStatement(
        'ALTER TABLE tags ADD COLUMN description TEXT',
      );
    }
    if (!tagColumns.contains('color_value')) {
      await database.customStatement(
        'ALTER TABLE tags ADD COLUMN color_value INTEGER NOT NULL DEFAULT $kDefaultTagColorValue',
      );
    }
    if (!tagColumns.contains('icon_key')) {
      await database.customStatement(
        "ALTER TABLE tags ADD COLUMN icon_key TEXT NOT NULL DEFAULT '$kDefaultTagIconKey'",
      );
    }
    if (!tagColumns.contains('parent_tag_id')) {
      await database.customStatement(
        'ALTER TABLE tags ADD COLUMN parent_tag_id INTEGER',
      );
    }
    if (!tagColumns.contains('sort_order')) {
      await database.customStatement(
        'ALTER TABLE tags ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!tagColumns.contains('created_at')) {
      await database.customStatement(
        'ALTER TABLE tags ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!tagColumns.contains('updated_at')) {
      await database.customStatement(
        'ALTER TABLE tags ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!tagColumns.contains('archived_at')) {
      await database.customStatement(
        'ALTER TABLE tags ADD COLUMN archived_at INTEGER',
      );
    }
    if (!tagColumns.contains('scope')) {
      await database.customStatement(
        "ALTER TABLE tags ADD COLUMN scope TEXT NOT NULL DEFAULT '$kTagScopeDocument'",
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await database.customStatement(
      'UPDATE tags SET archived_at = NULL WHERE archived_at = 0',
    );
    await database.customStatement(
      'UPDATE tags SET created_at = ? WHERE created_at = 0',
      [now],
    );
    await database.customStatement(
      'UPDATE tags SET updated_at = ? WHERE updated_at = 0',
      [now],
    );

    _schemaReady = true;
  }

  Stream<List<AppTag>> watchTags({
    bool includeArchived = false,
    String? scope = kTagScopeDocument,
  }) async* {
    await ensureSchema();

    final conditions = <String>[];
    if (!includeArchived) {
      conditions.add('(archived_at IS NULL OR archived_at <= 0)');
    }
    if (scope != null) {
      conditions.add("(scope = '$kTagScopeBoth' OR scope = ?)");
    }
    final whereClause = conditions.isEmpty
        ? ''
        : 'WHERE ${conditions.join(' AND ')}';
    final variables = <drift.Variable>[
      if (scope != null) drift.Variable.withString(scope),
    ];

    yield* database
        .customSelect(
          '''
SELECT
  id,
  name,
  description,
  color_value,
  icon_key,
  parent_tag_id,
  sort_order,
  created_at,
  updated_at,
  archived_at,
  scope
FROM tags
$whereClause
ORDER BY sort_order ASC, lower(name) ASC
''',
          variables: variables,
          readsFrom: {database.tags},
        )
        .watch()
        .map((rows) => rows.map(_tagFromRow).toList());
  }

  Future<List<AppTag>> getTags({
    bool includeArchived = false,
    String? scope = kTagScopeDocument,
  }) async {
    await ensureSchema();

    final conditions = <String>[];
    if (!includeArchived) {
      conditions.add('(archived_at IS NULL OR archived_at <= 0)');
    }
    if (scope != null) {
      conditions.add("(scope = '$kTagScopeBoth' OR scope = ?)");
    }
    final whereClause = conditions.isEmpty
        ? ''
        : 'WHERE ${conditions.join(' AND ')}';
    final variables = <drift.Variable>[
      if (scope != null) drift.Variable.withString(scope),
    ];

    final rows = await database.customSelect('''
SELECT
  id,
  name,
  description,
  color_value,
  icon_key,
  parent_tag_id,
  sort_order,
  created_at,
  updated_at,
  archived_at,
  scope
FROM tags
$whereClause
ORDER BY sort_order ASC, lower(name) ASC
''', variables: variables).get();

    return rows.map(_tagFromRow).toList();
  }

  Future<int> createTag({
    required String name,
    String? description,
    int colorValue = kDefaultTagColorValue,
    String iconKey = kDefaultTagIconKey,
    int? parentTagId,
    String scope = kTagScopeDocument,
  }) async {
    await ensureSchema();

    final cleanedName = name.trim();
    if (cleanedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Tag name cannot be empty.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    await database.customStatement(
      '''
INSERT INTO tags (
  name,
  description,
  color_value,
  icon_key,
  parent_tag_id,
  sort_order,
  created_at,
  updated_at,
  archived_at,
  scope
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
''',
      [
        cleanedName,
        _emptyToNull(description),
        colorValue,
        iconKey,
        parentTagId,
        0,
        now,
        now,
        _normalizeTagScope(scope),
      ],
    );

    final idRow = await database
        .customSelect('SELECT last_insert_rowid() AS id')
        .getSingle();

    return idRow.read<int>('id');
  }

  Future<void> updateTag({
    required int tagId,
    required String name,
    String? description,
    required int colorValue,
    required String iconKey,
    int? parentTagId,
    int? sortOrder,
    String? scope,
  }) async {
    await ensureSchema();

    final cleanedName = name.trim();
    if (cleanedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Tag name cannot be empty.');
    }

    await database.customStatement(
      '''
UPDATE tags
SET
  name = ?,
  description = ?,
  color_value = ?,
  icon_key = ?,
  parent_tag_id = ?,
  sort_order = ?,
  scope = COALESCE(?, scope),
  updated_at = ?
WHERE id = ?
''',
      [
        cleanedName,
        _emptyToNull(description),
        colorValue,
        iconKey,
        parentTagId,
        sortOrder ?? 0,
        scope == null ? null : _normalizeTagScope(scope),
        DateTime.now().millisecondsSinceEpoch,
        tagId,
      ],
    );
  }

  Future<void> archiveTag(int tagId) async {
    await ensureSchema();

    final now = DateTime.now().millisecondsSinceEpoch;
    await database.customStatement(
      'UPDATE tags SET archived_at = ?, updated_at = ? WHERE id = ?',
      [now, now, tagId],
    );
  }

  Future<void> restoreTag(int tagId) async {
    await ensureSchema();

    await database.customStatement(
      'UPDATE tags SET archived_at = NULL, updated_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, tagId],
    );
  }

  Future<void> deleteTagPermanently(int tagId) async {
    await ensureSchema();

    await database.transaction(() async {
      await database.customUpdate(
        'DELETE FROM document_tags WHERE tag_id = ?',
        variables: [drift.Variable.withInt(tagId)],
        updates: {database.documentTags},
      );
      await database.customStatement(
        'DELETE FROM tag_assignments WHERE tag_id = ?',
        [tagId],
      );
      await database.customStatement('DELETE FROM tags WHERE id = ?', [tagId]);
    });
  }

  Future<void> assignTag({
    required int tagId,
    required String targetType,
    required String targetId,
    String? documentId,
  }) async {
    await ensureSchema();

    final id = _assignmentId(tagId, targetType, targetId);
    await database.customStatement(
      '''
INSERT OR IGNORE INTO tag_assignments (
  id,
  tag_id,
  target_type,
  target_id,
  document_id,
  created_at
) VALUES (?, ?, ?, ?, ?, ?)
''',
      [
        id,
        tagId,
        targetType,
        targetId,
        documentId,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> unassignTag({
    required int tagId,
    required String targetType,
    required String targetId,
  }) async {
    await ensureSchema();

    await database.customStatement(
      '''
DELETE FROM tag_assignments
WHERE tag_id = ? AND target_type = ? AND target_id = ?
''',
      [tagId, targetType, targetId],
    );
  }

  Future<List<TagAssignment>> getAssignmentsForTarget({
    required String targetType,
    required String targetId,
  }) async {
    await ensureSchema();

    final rows = await database
        .customSelect(
          '''
SELECT id, tag_id, target_type, target_id, document_id, created_at
FROM tag_assignments
WHERE target_type = ? AND target_id = ?
ORDER BY created_at ASC
''',
          variables: [
            drift.Variable.withString(targetType),
            drift.Variable.withString(targetId),
          ],
        )
        .get();

    return rows.map(_assignmentFromRow).toList();
  }

  Future<List<TagAssignment>> getAssignmentsForTag({
    required int tagId,
    String? targetType,
    String? documentId,
  }) async {
    await ensureSchema();

    final conditions = <String>['tag_id = ?'];
    final variables = <drift.Variable>[drift.Variable.withInt(tagId)];

    if (targetType != null) {
      conditions.add('target_type = ?');
      variables.add(drift.Variable.withString(targetType));
    }

    if (documentId != null) {
      conditions.add('document_id = ?');
      variables.add(drift.Variable.withString(documentId));
    }

    final rows = await database.customSelect('''
SELECT id, tag_id, target_type, target_id, document_id, created_at
FROM tag_assignments
WHERE ${conditions.join(' AND ')}
ORDER BY created_at DESC
''', variables: variables).get();

    return rows.map(_assignmentFromRow).toList();
  }

  Stream<Map<String, List<AppTag>>> watchDocumentTagMap() async* {
    await ensureSchema();

    yield* database
        .customSelect(
          '''
SELECT
  document_tags.document_id AS document_id,
  tags.id,
  tags.name,
  tags.description,
  tags.color_value,
  tags.icon_key,
  tags.parent_tag_id,
  tags.sort_order,
  tags.created_at,
  tags.updated_at,
  tags.archived_at,
  tags.scope
FROM document_tags
INNER JOIN tags ON tags.id = document_tags.tag_id
WHERE (tags.archived_at IS NULL OR tags.archived_at <= 0)
ORDER BY tags.sort_order ASC, lower(tags.name) ASC
''',
          readsFrom: {database.documentTags, database.tags},
        )
        .watch()
        .map((rows) {
          final result = <String, List<AppTag>>{};

          for (final row in rows) {
            final documentId = row.read<String>('document_id');
            result.putIfAbsent(documentId, () => []).add(_tagFromRow(row));
          }

          return result;
        });
  }

  Future<List<AppTag>> getDocumentTags(String documentId) async {
    await ensureSchema();

    final rows = await database
        .customSelect(
          '''
SELECT
  tags.id,
  tags.name,
  tags.description,
  tags.color_value,
  tags.icon_key,
  tags.parent_tag_id,
  tags.sort_order,
  tags.created_at,
  tags.updated_at,
  tags.archived_at,
  tags.scope
FROM document_tags
INNER JOIN tags ON tags.id = document_tags.tag_id
WHERE document_tags.document_id = ? AND (tags.archived_at IS NULL OR tags.archived_at <= 0)
ORDER BY tags.sort_order ASC, lower(tags.name) ASC
''',
          variables: [drift.Variable.withString(documentId)],
          readsFrom: {database.documentTags, database.tags},
        )
        .get();

    return rows.map(_tagFromRow).toList();
  }

  Future<void> assignDocumentTag({
    required String documentId,
    required int tagId,
  }) async {
    await ensureSchema();

    await database.customUpdate(
      '''
INSERT OR IGNORE INTO document_tags (document_id, tag_id)
VALUES (?, ?)
''',
      variables: [
        drift.Variable.withString(documentId),
        drift.Variable.withInt(tagId),
      ],
      updates: {database.documentTags},
    );

    await assignTag(
      tagId: tagId,
      targetType: kTagTargetDocument,
      targetId: documentId,
      documentId: documentId,
    );
  }

  Future<void> unassignDocumentTag({
    required String documentId,
    required int tagId,
  }) async {
    await ensureSchema();

    await database.customUpdate(
      '''
DELETE FROM document_tags
WHERE document_id = ? AND tag_id = ?
''',
      variables: [
        drift.Variable.withString(documentId),
        drift.Variable.withInt(tagId),
      ],
      updates: {database.documentTags},
    );

    await unassignTag(
      tagId: tagId,
      targetType: kTagTargetDocument,
      targetId: documentId,
    );
  }

  Stream<List<AppTag>> watchTagsForTarget({
    required String targetType,
    required String targetId,
    bool includeArchived = false,
  }) async* {
    await ensureSchema();

    final archivedCondition = includeArchived
        ? ''
        : 'AND (tags.archived_at IS NULL OR tags.archived_at <= 0)';

    yield* database
        .customSelect(
          '''
SELECT
  tags.id,
  tags.name,
  tags.description,
  tags.color_value,
  tags.icon_key,
  tags.parent_tag_id,
  tags.sort_order,
  tags.created_at,
  tags.updated_at,
  tags.archived_at,
  tags.scope
FROM tag_assignments
INNER JOIN tags ON tags.id = tag_assignments.tag_id
WHERE tag_assignments.target_type = ?
  AND tag_assignments.target_id = ?
  $archivedCondition
ORDER BY tags.sort_order ASC, lower(tags.name) ASC
''',
          variables: [
            drift.Variable.withString(targetType),
            drift.Variable.withString(targetId),
          ],
          readsFrom: {database.tags},
        )
        .watch()
        .map((rows) => rows.map(_tagFromRow).toList());
  }

  Future<AppTag> findOrCreateKnowledgeTag(String rawName) async {
    await ensureSchema();

    final cleanedName = _normalizeKnowledgeTagName(rawName);
    if (cleanedName == null) {
      throw ArgumentError.value(rawName, 'rawName', 'Knowledge tag is empty.');
    }

    final existing = await database
        .customSelect(
          '''
SELECT
  id,
  name,
  description,
  color_value,
  icon_key,
  parent_tag_id,
  sort_order,
  created_at,
  updated_at,
  archived_at,
  scope
FROM tags
WHERE lower(name) = lower(?)
  AND (scope = ? OR scope = ?)
LIMIT 1
''',
          variables: [
            drift.Variable.withString(cleanedName),
            drift.Variable.withString(kTagScopeKnowledge),
            drift.Variable.withString(kTagScopeBoth),
          ],
        )
        .getSingleOrNull();

    if (existing != null) {
      return _tagFromRow(existing);
    }

    final tagId = await createTag(
      name: cleanedName,
      iconKey: kDefaultKnowledgeTagIconKey,
      scope: kTagScopeKnowledge,
    );

    final rows = await database
        .customSelect(
          '''
SELECT
  id,
  name,
  description,
  color_value,
  icon_key,
  parent_tag_id,
  sort_order,
  created_at,
  updated_at,
  archived_at,
  scope
FROM tags
WHERE id = ?
LIMIT 1
''',
          variables: [drift.Variable.withInt(tagId)],
        )
        .get();

    return _tagFromRow(rows.single);
  }

  Future<void> syncKnowledgeTagsForTarget({
    required String targetType,
    required String targetId,
    required String? documentId,
    required Iterable<String> tagNames,
  }) async {
    await ensureSchema();

    final normalizedNames = <String>{};
    for (final tagName in tagNames) {
      final normalized = _normalizeKnowledgeTagName(tagName);
      if (normalized != null) {
        normalizedNames.add(normalized);
      }
    }

    final tags = <AppTag>[];
    for (final tagName in normalizedNames) {
      tags.add(await findOrCreateKnowledgeTag(tagName));
    }

    await database.transaction(() async {
      await database.customStatement(
        '''
DELETE FROM tag_assignments
WHERE target_type = ?
  AND target_id = ?
  AND tag_id IN (
    SELECT id FROM tags WHERE scope = ? OR scope = ?
  )
''',
        [targetType, targetId, kTagScopeKnowledge, kTagScopeBoth],
      );

      for (final tag in tags) {
        await assignTag(
          tagId: tag.id,
          targetType: targetType,
          targetId: targetId,
          documentId: documentId,
        );
      }
    });
  }

  Future<Map<int, TagUsageSummary>> getUsageSummaries() async {
    await ensureSchema();

    final rows = await database.customSelect('''
SELECT
  tag_id,
  COUNT(*) AS total_count,
  SUM(CASE WHEN target_type = '$kTagTargetDocument' THEN 1 ELSE 0 END) AS document_count,
  SUM(CASE WHEN target_type IN ('$kTagTargetSidecarNote', '$kTagTargetDocumentNote') THEN 1 ELSE 0 END) AS note_count,
  SUM(CASE WHEN target_type = '$kTagTargetTodo' THEN 1 ELSE 0 END) AS todo_count,
  SUM(CASE WHEN target_type = '$kTagTargetHighlight' THEN 1 ELSE 0 END) AS highlight_count
FROM tag_assignments
GROUP BY tag_id
''').get();

    return {
      for (final row in rows)
        row.read<int>('tag_id'): TagUsageSummary(
          tagId: row.read<int>('tag_id'),
          totalCount: row.read<int>('total_count'),
          documentCount: row.read<int>('document_count'),
          noteCount: row.read<int>('note_count'),
          todoCount: row.read<int>('todo_count'),
          highlightCount: row.read<int>('highlight_count'),
        ),
    };
  }

  Future<Map<int, TagUsageSummary>>
  getUsageSummariesWithLegacyDocumentTags() async {
    await ensureSchema();

    final assignmentCounts = await getUsageSummaries();
    final legacyRows = await database.customSelect('''
SELECT tag_id, COUNT(*) AS document_count
FROM document_tags
GROUP BY tag_id
''').get();

    final merged = Map<int, TagUsageSummary>.from(assignmentCounts);

    for (final row in legacyRows) {
      final tagId = row.read<int>('tag_id');
      final legacyDocumentCount = row.read<int>('document_count');
      final current = merged[tagId] ?? TagUsageSummary.empty;

      merged[tagId] = TagUsageSummary(
        tagId: tagId,
        totalCount: current.totalCount + legacyDocumentCount,
        documentCount: current.documentCount + legacyDocumentCount,
        noteCount: current.noteCount,
        todoCount: current.todoCount,
        highlightCount: current.highlightCount,
      );
    }

    return merged;
  }

  AppTag _tagFromRow(dynamic row) {
    return AppTag(
      id: row.read<int>('id'),
      name: row.read<String>('name'),
      description: row.readNullable<String>('description'),
      colorValue: row.read<int>('color_value'),
      iconKey: row.read<String>('icon_key'),
      parentTagId: row.readNullable<int>('parent_tag_id'),
      sortOrder: row.read<int>('sort_order'),
      scope: _normalizeTagScope(row.read<String>('scope')),
      createdAt: _dateTimeFromMillis(row.read<int>('created_at')),
      updatedAt: _dateTimeFromMillis(row.read<int>('updated_at')),
      archivedAt: _nullableDateTimeFromMillis(
        row.readNullable<int>('archived_at'),
      ),
    );
  }

  TagAssignment _assignmentFromRow(dynamic row) {
    return TagAssignment(
      id: row.read<String>('id'),
      tagId: row.read<int>('tag_id'),
      targetType: row.read<String>('target_type'),
      targetId: row.read<String>('target_id'),
      documentId: row.readNullable<String>('document_id'),
      createdAt: _dateTimeFromMillis(row.read<int>('created_at')),
    );
  }

  Future<Set<String>> _tableColumns(String tableName) async {
    final rows = await database
        .customSelect('PRAGMA table_info($tableName)')
        .get();
    return {for (final row in rows) row.read<String>('name')};
  }

  DateTime _dateTimeFromMillis(int millis) {
    if (millis <= 0) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  DateTime? _nullableDateTimeFromMillis(int? millis) {
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  String _assignmentId(int tagId, String targetType, String targetId) {
    return '$tagId::$targetType::$targetId';
  }

  String _normalizeTagScope(String value) {
    switch (value.trim()) {
      case kTagScopeKnowledge:
        return kTagScopeKnowledge;
      case kTagScopeBoth:
        return kTagScopeBoth;
      case kTagScopeDocument:
      default:
        return kTagScopeDocument;
    }
  }

  String? _normalizeKnowledgeTagName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final withoutHash = trimmed.startsWith('#')
        ? trimmed.substring(1)
        : trimmed;
    final compact = withoutHash
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'^[-_/]+|[-_/]+$'), '')
        .toLowerCase();
    if (compact.isEmpty) return null;
    return compact;
  }

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
