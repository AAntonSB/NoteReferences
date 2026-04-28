// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PdfDocumentsTable extends PdfDocuments
    with TableInfo<$PdfDocumentsTable, PdfDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PdfDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalFileNameMeta = const VerificationMeta(
    'originalFileName',
  );
  @override
  late final GeneratedColumn<String> originalFileName = GeneratedColumn<String>(
    'original_file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorsMeta = const VerificationMeta(
    'authors',
  );
  @override
  late final GeneratedColumn<String> authors = GeneratedColumn<String>(
    'authors',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fieldOfStudyMeta = const VerificationMeta(
    'fieldOfStudy',
  );
  @override
  late final GeneratedColumn<String> fieldOfStudy = GeneratedColumn<String>(
    'field_of_study',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isbnMeta = const VerificationMeta('isbn');
  @override
  late final GeneratedColumn<String> isbn = GeneratedColumn<String>(
    'isbn',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doiMeta = const VerificationMeta('doi');
  @override
  late final GeneratedColumn<String> doi = GeneratedColumn<String>(
    'doi',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _issnMeta = const VerificationMeta('issn');
  @override
  late final GeneratedColumn<String> issn = GeneratedColumn<String>(
    'issn',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _arxivIdMeta = const VerificationMeta(
    'arxivId',
  );
  @override
  late final GeneratedColumn<String> arxivId = GeneratedColumn<String>(
    'arxiv_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _journalMeta = const VerificationMeta(
    'journal',
  );
  @override
  late final GeneratedColumn<String> journal = GeneratedColumn<String>(
    'journal',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publisherMeta = const VerificationMeta(
    'publisher',
  );
  @override
  late final GeneratedColumn<String> publisher = GeneratedColumn<String>(
    'publisher',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _keywordsMeta = const VerificationMeta(
    'keywords',
  );
  @override
  late final GeneratedColumn<String> keywords = GeneratedColumn<String>(
    'keywords',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileLastModifiedAtMeta =
      const VerificationMeta('fileLastModifiedAt');
  @override
  late final GeneratedColumn<DateTime> fileLastModifiedAt =
      GeneratedColumn<DateTime>(
        'file_last_modified_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _metadataLastEditedAtMeta =
      const VerificationMeta('metadataLastEditedAt');
  @override
  late final GeneratedColumn<DateTime> metadataLastEditedAt =
      GeneratedColumn<DateTime>(
        'metadata_last_edited_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    documentId,
    filePath,
    originalFileName,
    name,
    authors,
    subject,
    fieldOfStudy,
    isbn,
    doi,
    issn,
    arxivId,
    journal,
    publisher,
    keywords,
    addedAt,
    fileLastModifiedAt,
    metadataLastEditedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pdf_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<PdfDocument> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('original_file_name')) {
      context.handle(
        _originalFileNameMeta,
        originalFileName.isAcceptableOrUnknown(
          data['original_file_name']!,
          _originalFileNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalFileNameMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('authors')) {
      context.handle(
        _authorsMeta,
        authors.isAcceptableOrUnknown(data['authors']!, _authorsMeta),
      );
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    }
    if (data.containsKey('field_of_study')) {
      context.handle(
        _fieldOfStudyMeta,
        fieldOfStudy.isAcceptableOrUnknown(
          data['field_of_study']!,
          _fieldOfStudyMeta,
        ),
      );
    }
    if (data.containsKey('isbn')) {
      context.handle(
        _isbnMeta,
        isbn.isAcceptableOrUnknown(data['isbn']!, _isbnMeta),
      );
    }
    if (data.containsKey('doi')) {
      context.handle(
        _doiMeta,
        doi.isAcceptableOrUnknown(data['doi']!, _doiMeta),
      );
    }
    if (data.containsKey('issn')) {
      context.handle(
        _issnMeta,
        issn.isAcceptableOrUnknown(data['issn']!, _issnMeta),
      );
    }
    if (data.containsKey('arxiv_id')) {
      context.handle(
        _arxivIdMeta,
        arxivId.isAcceptableOrUnknown(data['arxiv_id']!, _arxivIdMeta),
      );
    }
    if (data.containsKey('journal')) {
      context.handle(
        _journalMeta,
        journal.isAcceptableOrUnknown(data['journal']!, _journalMeta),
      );
    }
    if (data.containsKey('publisher')) {
      context.handle(
        _publisherMeta,
        publisher.isAcceptableOrUnknown(data['publisher']!, _publisherMeta),
      );
    }
    if (data.containsKey('keywords')) {
      context.handle(
        _keywordsMeta,
        keywords.isAcceptableOrUnknown(data['keywords']!, _keywordsMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('file_last_modified_at')) {
      context.handle(
        _fileLastModifiedAtMeta,
        fileLastModifiedAt.isAcceptableOrUnknown(
          data['file_last_modified_at']!,
          _fileLastModifiedAtMeta,
        ),
      );
    }
    if (data.containsKey('metadata_last_edited_at')) {
      context.handle(
        _metadataLastEditedAtMeta,
        metadataLastEditedAt.isAcceptableOrUnknown(
          data['metadata_last_edited_at']!,
          _metadataLastEditedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId};
  @override
  PdfDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PdfDocument(
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      originalFileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_file_name'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      authors: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}authors'],
      ),
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      ),
      fieldOfStudy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_of_study'],
      ),
      isbn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}isbn'],
      ),
      doi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doi'],
      ),
      issn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}issn'],
      ),
      arxivId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}arxiv_id'],
      ),
      journal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}journal'],
      ),
      publisher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher'],
      ),
      keywords: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}keywords'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      fileLastModifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}file_last_modified_at'],
      ),
      metadataLastEditedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}metadata_last_edited_at'],
      ),
    );
  }

  @override
  $PdfDocumentsTable createAlias(String alias) {
    return $PdfDocumentsTable(attachedDatabase, alias);
  }
}

class PdfDocument extends DataClass implements Insertable<PdfDocument> {
  final String documentId;
  final String filePath;
  final String originalFileName;
  final String name;
  final String? authors;
  final String? subject;
  final String? fieldOfStudy;
  final String? isbn;
  final String? doi;
  final String? issn;
  final String? arxivId;
  final String? journal;
  final String? publisher;
  final String? keywords;
  final DateTime addedAt;
  final DateTime? fileLastModifiedAt;
  final DateTime? metadataLastEditedAt;
  const PdfDocument({
    required this.documentId,
    required this.filePath,
    required this.originalFileName,
    required this.name,
    this.authors,
    this.subject,
    this.fieldOfStudy,
    this.isbn,
    this.doi,
    this.issn,
    this.arxivId,
    this.journal,
    this.publisher,
    this.keywords,
    required this.addedAt,
    this.fileLastModifiedAt,
    this.metadataLastEditedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<String>(documentId);
    map['file_path'] = Variable<String>(filePath);
    map['original_file_name'] = Variable<String>(originalFileName);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || authors != null) {
      map['authors'] = Variable<String>(authors);
    }
    if (!nullToAbsent || subject != null) {
      map['subject'] = Variable<String>(subject);
    }
    if (!nullToAbsent || fieldOfStudy != null) {
      map['field_of_study'] = Variable<String>(fieldOfStudy);
    }
    if (!nullToAbsent || isbn != null) {
      map['isbn'] = Variable<String>(isbn);
    }
    if (!nullToAbsent || doi != null) {
      map['doi'] = Variable<String>(doi);
    }
    if (!nullToAbsent || issn != null) {
      map['issn'] = Variable<String>(issn);
    }
    if (!nullToAbsent || arxivId != null) {
      map['arxiv_id'] = Variable<String>(arxivId);
    }
    if (!nullToAbsent || journal != null) {
      map['journal'] = Variable<String>(journal);
    }
    if (!nullToAbsent || publisher != null) {
      map['publisher'] = Variable<String>(publisher);
    }
    if (!nullToAbsent || keywords != null) {
      map['keywords'] = Variable<String>(keywords);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    if (!nullToAbsent || fileLastModifiedAt != null) {
      map['file_last_modified_at'] = Variable<DateTime>(fileLastModifiedAt);
    }
    if (!nullToAbsent || metadataLastEditedAt != null) {
      map['metadata_last_edited_at'] = Variable<DateTime>(metadataLastEditedAt);
    }
    return map;
  }

  PdfDocumentsCompanion toCompanion(bool nullToAbsent) {
    return PdfDocumentsCompanion(
      documentId: Value(documentId),
      filePath: Value(filePath),
      originalFileName: Value(originalFileName),
      name: Value(name),
      authors: authors == null && nullToAbsent
          ? const Value.absent()
          : Value(authors),
      subject: subject == null && nullToAbsent
          ? const Value.absent()
          : Value(subject),
      fieldOfStudy: fieldOfStudy == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldOfStudy),
      isbn: isbn == null && nullToAbsent ? const Value.absent() : Value(isbn),
      doi: doi == null && nullToAbsent ? const Value.absent() : Value(doi),
      issn: issn == null && nullToAbsent ? const Value.absent() : Value(issn),
      arxivId: arxivId == null && nullToAbsent
          ? const Value.absent()
          : Value(arxivId),
      journal: journal == null && nullToAbsent
          ? const Value.absent()
          : Value(journal),
      publisher: publisher == null && nullToAbsent
          ? const Value.absent()
          : Value(publisher),
      keywords: keywords == null && nullToAbsent
          ? const Value.absent()
          : Value(keywords),
      addedAt: Value(addedAt),
      fileLastModifiedAt: fileLastModifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(fileLastModifiedAt),
      metadataLastEditedAt: metadataLastEditedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataLastEditedAt),
    );
  }

  factory PdfDocument.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PdfDocument(
      documentId: serializer.fromJson<String>(json['documentId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      originalFileName: serializer.fromJson<String>(json['originalFileName']),
      name: serializer.fromJson<String>(json['name']),
      authors: serializer.fromJson<String?>(json['authors']),
      subject: serializer.fromJson<String?>(json['subject']),
      fieldOfStudy: serializer.fromJson<String?>(json['fieldOfStudy']),
      isbn: serializer.fromJson<String?>(json['isbn']),
      doi: serializer.fromJson<String?>(json['doi']),
      issn: serializer.fromJson<String?>(json['issn']),
      arxivId: serializer.fromJson<String?>(json['arxivId']),
      journal: serializer.fromJson<String?>(json['journal']),
      publisher: serializer.fromJson<String?>(json['publisher']),
      keywords: serializer.fromJson<String?>(json['keywords']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      fileLastModifiedAt: serializer.fromJson<DateTime?>(
        json['fileLastModifiedAt'],
      ),
      metadataLastEditedAt: serializer.fromJson<DateTime?>(
        json['metadataLastEditedAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<String>(documentId),
      'filePath': serializer.toJson<String>(filePath),
      'originalFileName': serializer.toJson<String>(originalFileName),
      'name': serializer.toJson<String>(name),
      'authors': serializer.toJson<String?>(authors),
      'subject': serializer.toJson<String?>(subject),
      'fieldOfStudy': serializer.toJson<String?>(fieldOfStudy),
      'isbn': serializer.toJson<String?>(isbn),
      'doi': serializer.toJson<String?>(doi),
      'issn': serializer.toJson<String?>(issn),
      'arxivId': serializer.toJson<String?>(arxivId),
      'journal': serializer.toJson<String?>(journal),
      'publisher': serializer.toJson<String?>(publisher),
      'keywords': serializer.toJson<String?>(keywords),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'fileLastModifiedAt': serializer.toJson<DateTime?>(fileLastModifiedAt),
      'metadataLastEditedAt': serializer.toJson<DateTime?>(
        metadataLastEditedAt,
      ),
    };
  }

  PdfDocument copyWith({
    String? documentId,
    String? filePath,
    String? originalFileName,
    String? name,
    Value<String?> authors = const Value.absent(),
    Value<String?> subject = const Value.absent(),
    Value<String?> fieldOfStudy = const Value.absent(),
    Value<String?> isbn = const Value.absent(),
    Value<String?> doi = const Value.absent(),
    Value<String?> issn = const Value.absent(),
    Value<String?> arxivId = const Value.absent(),
    Value<String?> journal = const Value.absent(),
    Value<String?> publisher = const Value.absent(),
    Value<String?> keywords = const Value.absent(),
    DateTime? addedAt,
    Value<DateTime?> fileLastModifiedAt = const Value.absent(),
    Value<DateTime?> metadataLastEditedAt = const Value.absent(),
  }) => PdfDocument(
    documentId: documentId ?? this.documentId,
    filePath: filePath ?? this.filePath,
    originalFileName: originalFileName ?? this.originalFileName,
    name: name ?? this.name,
    authors: authors.present ? authors.value : this.authors,
    subject: subject.present ? subject.value : this.subject,
    fieldOfStudy: fieldOfStudy.present ? fieldOfStudy.value : this.fieldOfStudy,
    isbn: isbn.present ? isbn.value : this.isbn,
    doi: doi.present ? doi.value : this.doi,
    issn: issn.present ? issn.value : this.issn,
    arxivId: arxivId.present ? arxivId.value : this.arxivId,
    journal: journal.present ? journal.value : this.journal,
    publisher: publisher.present ? publisher.value : this.publisher,
    keywords: keywords.present ? keywords.value : this.keywords,
    addedAt: addedAt ?? this.addedAt,
    fileLastModifiedAt: fileLastModifiedAt.present
        ? fileLastModifiedAt.value
        : this.fileLastModifiedAt,
    metadataLastEditedAt: metadataLastEditedAt.present
        ? metadataLastEditedAt.value
        : this.metadataLastEditedAt,
  );
  PdfDocument copyWithCompanion(PdfDocumentsCompanion data) {
    return PdfDocument(
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      originalFileName: data.originalFileName.present
          ? data.originalFileName.value
          : this.originalFileName,
      name: data.name.present ? data.name.value : this.name,
      authors: data.authors.present ? data.authors.value : this.authors,
      subject: data.subject.present ? data.subject.value : this.subject,
      fieldOfStudy: data.fieldOfStudy.present
          ? data.fieldOfStudy.value
          : this.fieldOfStudy,
      isbn: data.isbn.present ? data.isbn.value : this.isbn,
      doi: data.doi.present ? data.doi.value : this.doi,
      issn: data.issn.present ? data.issn.value : this.issn,
      arxivId: data.arxivId.present ? data.arxivId.value : this.arxivId,
      journal: data.journal.present ? data.journal.value : this.journal,
      publisher: data.publisher.present ? data.publisher.value : this.publisher,
      keywords: data.keywords.present ? data.keywords.value : this.keywords,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      fileLastModifiedAt: data.fileLastModifiedAt.present
          ? data.fileLastModifiedAt.value
          : this.fileLastModifiedAt,
      metadataLastEditedAt: data.metadataLastEditedAt.present
          ? data.metadataLastEditedAt.value
          : this.metadataLastEditedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PdfDocument(')
          ..write('documentId: $documentId, ')
          ..write('filePath: $filePath, ')
          ..write('originalFileName: $originalFileName, ')
          ..write('name: $name, ')
          ..write('authors: $authors, ')
          ..write('subject: $subject, ')
          ..write('fieldOfStudy: $fieldOfStudy, ')
          ..write('isbn: $isbn, ')
          ..write('doi: $doi, ')
          ..write('issn: $issn, ')
          ..write('arxivId: $arxivId, ')
          ..write('journal: $journal, ')
          ..write('publisher: $publisher, ')
          ..write('keywords: $keywords, ')
          ..write('addedAt: $addedAt, ')
          ..write('fileLastModifiedAt: $fileLastModifiedAt, ')
          ..write('metadataLastEditedAt: $metadataLastEditedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    documentId,
    filePath,
    originalFileName,
    name,
    authors,
    subject,
    fieldOfStudy,
    isbn,
    doi,
    issn,
    arxivId,
    journal,
    publisher,
    keywords,
    addedAt,
    fileLastModifiedAt,
    metadataLastEditedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PdfDocument &&
          other.documentId == this.documentId &&
          other.filePath == this.filePath &&
          other.originalFileName == this.originalFileName &&
          other.name == this.name &&
          other.authors == this.authors &&
          other.subject == this.subject &&
          other.fieldOfStudy == this.fieldOfStudy &&
          other.isbn == this.isbn &&
          other.doi == this.doi &&
          other.issn == this.issn &&
          other.arxivId == this.arxivId &&
          other.journal == this.journal &&
          other.publisher == this.publisher &&
          other.keywords == this.keywords &&
          other.addedAt == this.addedAt &&
          other.fileLastModifiedAt == this.fileLastModifiedAt &&
          other.metadataLastEditedAt == this.metadataLastEditedAt);
}

class PdfDocumentsCompanion extends UpdateCompanion<PdfDocument> {
  final Value<String> documentId;
  final Value<String> filePath;
  final Value<String> originalFileName;
  final Value<String> name;
  final Value<String?> authors;
  final Value<String?> subject;
  final Value<String?> fieldOfStudy;
  final Value<String?> isbn;
  final Value<String?> doi;
  final Value<String?> issn;
  final Value<String?> arxivId;
  final Value<String?> journal;
  final Value<String?> publisher;
  final Value<String?> keywords;
  final Value<DateTime> addedAt;
  final Value<DateTime?> fileLastModifiedAt;
  final Value<DateTime?> metadataLastEditedAt;
  final Value<int> rowid;
  const PdfDocumentsCompanion({
    this.documentId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.originalFileName = const Value.absent(),
    this.name = const Value.absent(),
    this.authors = const Value.absent(),
    this.subject = const Value.absent(),
    this.fieldOfStudy = const Value.absent(),
    this.isbn = const Value.absent(),
    this.doi = const Value.absent(),
    this.issn = const Value.absent(),
    this.arxivId = const Value.absent(),
    this.journal = const Value.absent(),
    this.publisher = const Value.absent(),
    this.keywords = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.fileLastModifiedAt = const Value.absent(),
    this.metadataLastEditedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PdfDocumentsCompanion.insert({
    required String documentId,
    required String filePath,
    required String originalFileName,
    required String name,
    this.authors = const Value.absent(),
    this.subject = const Value.absent(),
    this.fieldOfStudy = const Value.absent(),
    this.isbn = const Value.absent(),
    this.doi = const Value.absent(),
    this.issn = const Value.absent(),
    this.arxivId = const Value.absent(),
    this.journal = const Value.absent(),
    this.publisher = const Value.absent(),
    this.keywords = const Value.absent(),
    required DateTime addedAt,
    this.fileLastModifiedAt = const Value.absent(),
    this.metadataLastEditedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : documentId = Value(documentId),
       filePath = Value(filePath),
       originalFileName = Value(originalFileName),
       name = Value(name),
       addedAt = Value(addedAt);
  static Insertable<PdfDocument> custom({
    Expression<String>? documentId,
    Expression<String>? filePath,
    Expression<String>? originalFileName,
    Expression<String>? name,
    Expression<String>? authors,
    Expression<String>? subject,
    Expression<String>? fieldOfStudy,
    Expression<String>? isbn,
    Expression<String>? doi,
    Expression<String>? issn,
    Expression<String>? arxivId,
    Expression<String>? journal,
    Expression<String>? publisher,
    Expression<String>? keywords,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? fileLastModifiedAt,
    Expression<DateTime>? metadataLastEditedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (filePath != null) 'file_path': filePath,
      if (originalFileName != null) 'original_file_name': originalFileName,
      if (name != null) 'name': name,
      if (authors != null) 'authors': authors,
      if (subject != null) 'subject': subject,
      if (fieldOfStudy != null) 'field_of_study': fieldOfStudy,
      if (isbn != null) 'isbn': isbn,
      if (doi != null) 'doi': doi,
      if (issn != null) 'issn': issn,
      if (arxivId != null) 'arxiv_id': arxivId,
      if (journal != null) 'journal': journal,
      if (publisher != null) 'publisher': publisher,
      if (keywords != null) 'keywords': keywords,
      if (addedAt != null) 'added_at': addedAt,
      if (fileLastModifiedAt != null)
        'file_last_modified_at': fileLastModifiedAt,
      if (metadataLastEditedAt != null)
        'metadata_last_edited_at': metadataLastEditedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PdfDocumentsCompanion copyWith({
    Value<String>? documentId,
    Value<String>? filePath,
    Value<String>? originalFileName,
    Value<String>? name,
    Value<String?>? authors,
    Value<String?>? subject,
    Value<String?>? fieldOfStudy,
    Value<String?>? isbn,
    Value<String?>? doi,
    Value<String?>? issn,
    Value<String?>? arxivId,
    Value<String?>? journal,
    Value<String?>? publisher,
    Value<String?>? keywords,
    Value<DateTime>? addedAt,
    Value<DateTime?>? fileLastModifiedAt,
    Value<DateTime?>? metadataLastEditedAt,
    Value<int>? rowid,
  }) {
    return PdfDocumentsCompanion(
      documentId: documentId ?? this.documentId,
      filePath: filePath ?? this.filePath,
      originalFileName: originalFileName ?? this.originalFileName,
      name: name ?? this.name,
      authors: authors ?? this.authors,
      subject: subject ?? this.subject,
      fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
      isbn: isbn ?? this.isbn,
      doi: doi ?? this.doi,
      issn: issn ?? this.issn,
      arxivId: arxivId ?? this.arxivId,
      journal: journal ?? this.journal,
      publisher: publisher ?? this.publisher,
      keywords: keywords ?? this.keywords,
      addedAt: addedAt ?? this.addedAt,
      fileLastModifiedAt: fileLastModifiedAt ?? this.fileLastModifiedAt,
      metadataLastEditedAt: metadataLastEditedAt ?? this.metadataLastEditedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (originalFileName.present) {
      map['original_file_name'] = Variable<String>(originalFileName.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (authors.present) {
      map['authors'] = Variable<String>(authors.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (fieldOfStudy.present) {
      map['field_of_study'] = Variable<String>(fieldOfStudy.value);
    }
    if (isbn.present) {
      map['isbn'] = Variable<String>(isbn.value);
    }
    if (doi.present) {
      map['doi'] = Variable<String>(doi.value);
    }
    if (issn.present) {
      map['issn'] = Variable<String>(issn.value);
    }
    if (arxivId.present) {
      map['arxiv_id'] = Variable<String>(arxivId.value);
    }
    if (journal.present) {
      map['journal'] = Variable<String>(journal.value);
    }
    if (publisher.present) {
      map['publisher'] = Variable<String>(publisher.value);
    }
    if (keywords.present) {
      map['keywords'] = Variable<String>(keywords.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (fileLastModifiedAt.present) {
      map['file_last_modified_at'] = Variable<DateTime>(
        fileLastModifiedAt.value,
      );
    }
    if (metadataLastEditedAt.present) {
      map['metadata_last_edited_at'] = Variable<DateTime>(
        metadataLastEditedAt.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PdfDocumentsCompanion(')
          ..write('documentId: $documentId, ')
          ..write('filePath: $filePath, ')
          ..write('originalFileName: $originalFileName, ')
          ..write('name: $name, ')
          ..write('authors: $authors, ')
          ..write('subject: $subject, ')
          ..write('fieldOfStudy: $fieldOfStudy, ')
          ..write('isbn: $isbn, ')
          ..write('doi: $doi, ')
          ..write('issn: $issn, ')
          ..write('arxivId: $arxivId, ')
          ..write('journal: $journal, ')
          ..write('publisher: $publisher, ')
          ..write('keywords: $keywords, ')
          ..write('addedAt: $addedAt, ')
          ..write('fileLastModifiedAt: $fileLastModifiedAt, ')
          ..write('metadataLastEditedAt: $metadataLastEditedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PdfSessionsTable extends PdfSessions
    with TableInfo<$PdfSessionsTable, PdfSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PdfSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageNumberMeta = const VerificationMeta(
    'pageNumber',
  );
  @override
  late final GeneratedColumn<int> pageNumber = GeneratedColumn<int>(
    'page_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _scrollXMeta = const VerificationMeta(
    'scrollX',
  );
  @override
  late final GeneratedColumn<double> scrollX = GeneratedColumn<double>(
    'scroll_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _scrollYMeta = const VerificationMeta(
    'scrollY',
  );
  @override
  late final GeneratedColumn<double> scrollY = GeneratedColumn<double>(
    'scroll_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _zoomLevelMeta = const VerificationMeta(
    'zoomLevel',
  );
  @override
  late final GeneratedColumn<double> zoomLevel = GeneratedColumn<double>(
    'zoom_level',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1.0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    documentId,
    pageNumber,
    scrollX,
    scrollY,
    zoomLevel,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pdf_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PdfSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('page_number')) {
      context.handle(
        _pageNumberMeta,
        pageNumber.isAcceptableOrUnknown(data['page_number']!, _pageNumberMeta),
      );
    }
    if (data.containsKey('scroll_x')) {
      context.handle(
        _scrollXMeta,
        scrollX.isAcceptableOrUnknown(data['scroll_x']!, _scrollXMeta),
      );
    }
    if (data.containsKey('scroll_y')) {
      context.handle(
        _scrollYMeta,
        scrollY.isAcceptableOrUnknown(data['scroll_y']!, _scrollYMeta),
      );
    }
    if (data.containsKey('zoom_level')) {
      context.handle(
        _zoomLevelMeta,
        zoomLevel.isAcceptableOrUnknown(data['zoom_level']!, _zoomLevelMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId};
  @override
  PdfSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PdfSession(
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      pageNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_number'],
      )!,
      scrollX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}scroll_x'],
      )!,
      scrollY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}scroll_y'],
      )!,
      zoomLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}zoom_level'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PdfSessionsTable createAlias(String alias) {
    return $PdfSessionsTable(attachedDatabase, alias);
  }
}

class PdfSession extends DataClass implements Insertable<PdfSession> {
  final String documentId;
  final int pageNumber;
  final double scrollX;
  final double scrollY;
  final double zoomLevel;
  final DateTime updatedAt;
  const PdfSession({
    required this.documentId,
    required this.pageNumber,
    required this.scrollX,
    required this.scrollY,
    required this.zoomLevel,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<String>(documentId);
    map['page_number'] = Variable<int>(pageNumber);
    map['scroll_x'] = Variable<double>(scrollX);
    map['scroll_y'] = Variable<double>(scrollY);
    map['zoom_level'] = Variable<double>(zoomLevel);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PdfSessionsCompanion toCompanion(bool nullToAbsent) {
    return PdfSessionsCompanion(
      documentId: Value(documentId),
      pageNumber: Value(pageNumber),
      scrollX: Value(scrollX),
      scrollY: Value(scrollY),
      zoomLevel: Value(zoomLevel),
      updatedAt: Value(updatedAt),
    );
  }

  factory PdfSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PdfSession(
      documentId: serializer.fromJson<String>(json['documentId']),
      pageNumber: serializer.fromJson<int>(json['pageNumber']),
      scrollX: serializer.fromJson<double>(json['scrollX']),
      scrollY: serializer.fromJson<double>(json['scrollY']),
      zoomLevel: serializer.fromJson<double>(json['zoomLevel']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<String>(documentId),
      'pageNumber': serializer.toJson<int>(pageNumber),
      'scrollX': serializer.toJson<double>(scrollX),
      'scrollY': serializer.toJson<double>(scrollY),
      'zoomLevel': serializer.toJson<double>(zoomLevel),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PdfSession copyWith({
    String? documentId,
    int? pageNumber,
    double? scrollX,
    double? scrollY,
    double? zoomLevel,
    DateTime? updatedAt,
  }) => PdfSession(
    documentId: documentId ?? this.documentId,
    pageNumber: pageNumber ?? this.pageNumber,
    scrollX: scrollX ?? this.scrollX,
    scrollY: scrollY ?? this.scrollY,
    zoomLevel: zoomLevel ?? this.zoomLevel,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PdfSession copyWithCompanion(PdfSessionsCompanion data) {
    return PdfSession(
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      pageNumber: data.pageNumber.present
          ? data.pageNumber.value
          : this.pageNumber,
      scrollX: data.scrollX.present ? data.scrollX.value : this.scrollX,
      scrollY: data.scrollY.present ? data.scrollY.value : this.scrollY,
      zoomLevel: data.zoomLevel.present ? data.zoomLevel.value : this.zoomLevel,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PdfSession(')
          ..write('documentId: $documentId, ')
          ..write('pageNumber: $pageNumber, ')
          ..write('scrollX: $scrollX, ')
          ..write('scrollY: $scrollY, ')
          ..write('zoomLevel: $zoomLevel, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    documentId,
    pageNumber,
    scrollX,
    scrollY,
    zoomLevel,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PdfSession &&
          other.documentId == this.documentId &&
          other.pageNumber == this.pageNumber &&
          other.scrollX == this.scrollX &&
          other.scrollY == this.scrollY &&
          other.zoomLevel == this.zoomLevel &&
          other.updatedAt == this.updatedAt);
}

class PdfSessionsCompanion extends UpdateCompanion<PdfSession> {
  final Value<String> documentId;
  final Value<int> pageNumber;
  final Value<double> scrollX;
  final Value<double> scrollY;
  final Value<double> zoomLevel;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PdfSessionsCompanion({
    this.documentId = const Value.absent(),
    this.pageNumber = const Value.absent(),
    this.scrollX = const Value.absent(),
    this.scrollY = const Value.absent(),
    this.zoomLevel = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PdfSessionsCompanion.insert({
    required String documentId,
    this.pageNumber = const Value.absent(),
    this.scrollX = const Value.absent(),
    this.scrollY = const Value.absent(),
    this.zoomLevel = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : documentId = Value(documentId),
       updatedAt = Value(updatedAt);
  static Insertable<PdfSession> custom({
    Expression<String>? documentId,
    Expression<int>? pageNumber,
    Expression<double>? scrollX,
    Expression<double>? scrollY,
    Expression<double>? zoomLevel,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (pageNumber != null) 'page_number': pageNumber,
      if (scrollX != null) 'scroll_x': scrollX,
      if (scrollY != null) 'scroll_y': scrollY,
      if (zoomLevel != null) 'zoom_level': zoomLevel,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PdfSessionsCompanion copyWith({
    Value<String>? documentId,
    Value<int>? pageNumber,
    Value<double>? scrollX,
    Value<double>? scrollY,
    Value<double>? zoomLevel,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PdfSessionsCompanion(
      documentId: documentId ?? this.documentId,
      pageNumber: pageNumber ?? this.pageNumber,
      scrollX: scrollX ?? this.scrollX,
      scrollY: scrollY ?? this.scrollY,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (pageNumber.present) {
      map['page_number'] = Variable<int>(pageNumber.value);
    }
    if (scrollX.present) {
      map['scroll_x'] = Variable<double>(scrollX.value);
    }
    if (scrollY.present) {
      map['scroll_y'] = Variable<double>(scrollY.value);
    }
    if (zoomLevel.present) {
      map['zoom_level'] = Variable<double>(zoomLevel.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PdfSessionsCompanion(')
          ..write('documentId: $documentId, ')
          ..write('pageNumber: $pageNumber, ')
          ..write('scrollX: $scrollX, ')
          ..write('scrollY: $scrollY, ')
          ..write('zoomLevel: $zoomLevel, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  final int id;
  final String name;
  const Tag({required this.id, required this.name});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(id: Value(id), name: Value(name));
  }

  factory Tag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
    };
  }

  Tag copyWith({int? id, String? name}) =>
      Tag(id: id ?? this.id, name: name ?? this.name);
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag && other.id == this.id && other.name == this.name);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<int> id;
  final Value<String> name;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
  });
  TagsCompanion.insert({this.id = const Value.absent(), required String name})
    : name = Value(name);
  static Insertable<Tag> custom({
    Expression<int>? id,
    Expression<String>? name,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
    });
  }

  TagsCompanion copyWith({Value<int>? id, Value<String>? name}) {
    return TagsCompanion(id: id ?? this.id, name: name ?? this.name);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }
}

class $DocumentTagsTable extends DocumentTags
    with TableInfo<$DocumentTagsTable, DocumentTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<int> tagId = GeneratedColumn<int>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [documentId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'document_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<DocumentTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId, tagId};
  @override
  DocumentTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocumentTag(
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $DocumentTagsTable createAlias(String alias) {
    return $DocumentTagsTable(attachedDatabase, alias);
  }
}

class DocumentTag extends DataClass implements Insertable<DocumentTag> {
  final String documentId;
  final int tagId;
  const DocumentTag({required this.documentId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<String>(documentId);
    map['tag_id'] = Variable<int>(tagId);
    return map;
  }

  DocumentTagsCompanion toCompanion(bool nullToAbsent) {
    return DocumentTagsCompanion(
      documentId: Value(documentId),
      tagId: Value(tagId),
    );
  }

  factory DocumentTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocumentTag(
      documentId: serializer.fromJson<String>(json['documentId']),
      tagId: serializer.fromJson<int>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<String>(documentId),
      'tagId': serializer.toJson<int>(tagId),
    };
  }

  DocumentTag copyWith({String? documentId, int? tagId}) => DocumentTag(
    documentId: documentId ?? this.documentId,
    tagId: tagId ?? this.tagId,
  );
  DocumentTag copyWithCompanion(DocumentTagsCompanion data) {
    return DocumentTag(
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocumentTag(')
          ..write('documentId: $documentId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(documentId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocumentTag &&
          other.documentId == this.documentId &&
          other.tagId == this.tagId);
}

class DocumentTagsCompanion extends UpdateCompanion<DocumentTag> {
  final Value<String> documentId;
  final Value<int> tagId;
  final Value<int> rowid;
  const DocumentTagsCompanion({
    this.documentId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocumentTagsCompanion.insert({
    required String documentId,
    required int tagId,
    this.rowid = const Value.absent(),
  }) : documentId = Value(documentId),
       tagId = Value(tagId);
  static Insertable<DocumentTag> custom({
    Expression<String>? documentId,
    Expression<int>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocumentTagsCompanion copyWith({
    Value<String>? documentId,
    Value<int>? tagId,
    Value<int>? rowid,
  }) {
    return DocumentTagsCompanion(
      documentId: documentId ?? this.documentId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<int>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentTagsCompanion(')
          ..write('documentId: $documentId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, Note> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentNoteIdMeta = const VerificationMeta(
    'parentNoteId',
  );
  @override
  late final GeneratedColumn<String> parentNoteId = GeneratedColumn<String>(
    'parent_note_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteTypeMeta = const VerificationMeta(
    'noteType',
  );
  @override
  late final GeneratedColumn<String> noteType = GeneratedColumn<String>(
    'note_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('note'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    documentId,
    parentNoteId,
    title,
    noteType,
    createdAt,
    updatedAt,
    isArchived,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Note> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    }
    if (data.containsKey('parent_note_id')) {
      context.handle(
        _parentNoteIdMeta,
        parentNoteId.isAcceptableOrUnknown(
          data['parent_note_id']!,
          _parentNoteIdMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('note_type')) {
      context.handle(
        _noteTypeMeta,
        noteType.isAcceptableOrUnknown(data['note_type']!, _noteTypeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Note map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Note(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      ),
      parentNoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_note_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      noteType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_type'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class Note extends DataClass implements Insertable<Note> {
  final String id;

  /// Nullable because future notes may be free-standing project notes.
  final String? documentId;
  final String? parentNoteId;
  final String? title;

  /// Examples:
  /// note, question, summary, task, flashcard, citationNote
  final String noteType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
  const Note({
    required this.id,
    this.documentId,
    this.parentNoteId,
    this.title,
    required this.noteType,
    required this.createdAt,
    required this.updatedAt,
    required this.isArchived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || documentId != null) {
      map['document_id'] = Variable<String>(documentId);
    }
    if (!nullToAbsent || parentNoteId != null) {
      map['parent_note_id'] = Variable<String>(parentNoteId);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['note_type'] = Variable<String>(noteType);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_archived'] = Variable<bool>(isArchived);
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      documentId: documentId == null && nullToAbsent
          ? const Value.absent()
          : Value(documentId),
      parentNoteId: parentNoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentNoteId),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      noteType: Value(noteType),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isArchived: Value(isArchived),
    );
  }

  factory Note.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Note(
      id: serializer.fromJson<String>(json['id']),
      documentId: serializer.fromJson<String?>(json['documentId']),
      parentNoteId: serializer.fromJson<String?>(json['parentNoteId']),
      title: serializer.fromJson<String?>(json['title']),
      noteType: serializer.fromJson<String>(json['noteType']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'documentId': serializer.toJson<String?>(documentId),
      'parentNoteId': serializer.toJson<String?>(parentNoteId),
      'title': serializer.toJson<String?>(title),
      'noteType': serializer.toJson<String>(noteType),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isArchived': serializer.toJson<bool>(isArchived),
    };
  }

  Note copyWith({
    String? id,
    Value<String?> documentId = const Value.absent(),
    Value<String?> parentNoteId = const Value.absent(),
    Value<String?> title = const Value.absent(),
    String? noteType,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isArchived,
  }) => Note(
    id: id ?? this.id,
    documentId: documentId.present ? documentId.value : this.documentId,
    parentNoteId: parentNoteId.present ? parentNoteId.value : this.parentNoteId,
    title: title.present ? title.value : this.title,
    noteType: noteType ?? this.noteType,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isArchived: isArchived ?? this.isArchived,
  );
  Note copyWithCompanion(NotesCompanion data) {
    return Note(
      id: data.id.present ? data.id.value : this.id,
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      parentNoteId: data.parentNoteId.present
          ? data.parentNoteId.value
          : this.parentNoteId,
      title: data.title.present ? data.title.value : this.title,
      noteType: data.noteType.present ? data.noteType.value : this.noteType,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Note(')
          ..write('id: $id, ')
          ..write('documentId: $documentId, ')
          ..write('parentNoteId: $parentNoteId, ')
          ..write('title: $title, ')
          ..write('noteType: $noteType, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isArchived: $isArchived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    documentId,
    parentNoteId,
    title,
    noteType,
    createdAt,
    updatedAt,
    isArchived,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Note &&
          other.id == this.id &&
          other.documentId == this.documentId &&
          other.parentNoteId == this.parentNoteId &&
          other.title == this.title &&
          other.noteType == this.noteType &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isArchived == this.isArchived);
}

class NotesCompanion extends UpdateCompanion<Note> {
  final Value<String> id;
  final Value<String?> documentId;
  final Value<String?> parentNoteId;
  final Value<String?> title;
  final Value<String> noteType;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isArchived;
  final Value<int> rowid;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.documentId = const Value.absent(),
    this.parentNoteId = const Value.absent(),
    this.title = const Value.absent(),
    this.noteType = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    this.documentId = const Value.absent(),
    this.parentNoteId = const Value.absent(),
    this.title = const Value.absent(),
    this.noteType = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.isArchived = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Note> custom({
    Expression<String>? id,
    Expression<String>? documentId,
    Expression<String>? parentNoteId,
    Expression<String>? title,
    Expression<String>? noteType,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isArchived,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (documentId != null) 'document_id': documentId,
      if (parentNoteId != null) 'parent_note_id': parentNoteId,
      if (title != null) 'title': title,
      if (noteType != null) 'note_type': noteType,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isArchived != null) 'is_archived': isArchived,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesCompanion copyWith({
    Value<String>? id,
    Value<String?>? documentId,
    Value<String?>? parentNoteId,
    Value<String?>? title,
    Value<String>? noteType,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isArchived,
    Value<int>? rowid,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      parentNoteId: parentNoteId ?? this.parentNoteId,
      title: title ?? this.title,
      noteType: noteType ?? this.noteType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (parentNoteId.present) {
      map['parent_note_id'] = Variable<String>(parentNoteId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (noteType.present) {
      map['note_type'] = Variable<String>(noteType.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('documentId: $documentId, ')
          ..write('parentNoteId: $parentNoteId, ')
          ..write('title: $title, ')
          ..write('noteType: $noteType, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isArchived: $isArchived, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteBlocksTable extends NoteBlocks
    with TableInfo<$NoteBlocksTable, NoteBlock> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteBlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blockTypeMeta = const VerificationMeta(
    'blockType',
  );
  @override
  late final GeneratedColumn<String> blockType = GeneratedColumn<String>(
    'block_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  );
  static const VerificationMeta _contentTextMeta = const VerificationMeta(
    'contentText',
  );
  @override
  late final GeneratedColumn<String> contentText = GeneratedColumn<String>(
    'content_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentJsonMeta = const VerificationMeta(
    'contentJson',
  );
  @override
  late final GeneratedColumn<String> contentJson = GeneratedColumn<String>(
    'content_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    blockType,
    contentText,
    contentJson,
    sortOrder,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_blocks';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteBlock> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('block_type')) {
      context.handle(
        _blockTypeMeta,
        blockType.isAcceptableOrUnknown(data['block_type']!, _blockTypeMeta),
      );
    }
    if (data.containsKey('content_text')) {
      context.handle(
        _contentTextMeta,
        contentText.isAcceptableOrUnknown(
          data['content_text']!,
          _contentTextMeta,
        ),
      );
    }
    if (data.containsKey('content_json')) {
      context.handle(
        _contentJsonMeta,
        contentJson.isAcceptableOrUnknown(
          data['content_json']!,
          _contentJsonMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteBlock map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteBlock(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      blockType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}block_type'],
      )!,
      contentText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_text'],
      ),
      contentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_json'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NoteBlocksTable createAlias(String alias) {
    return $NoteBlocksTable(attachedDatabase, alias);
  }
}

class NoteBlock extends DataClass implements Insertable<NoteBlock> {
  final String id;
  final String noteId;

  /// Examples:
  /// text, heading, quote, image, inkDrawing, math, code, table, citation
  final String blockType;
  final String? contentText;

  /// Reserved for structured future block data.
  final String? contentJson;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  const NoteBlock({
    required this.id,
    required this.noteId,
    required this.blockType,
    this.contentText,
    this.contentJson,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    map['block_type'] = Variable<String>(blockType);
    if (!nullToAbsent || contentText != null) {
      map['content_text'] = Variable<String>(contentText);
    }
    if (!nullToAbsent || contentJson != null) {
      map['content_json'] = Variable<String>(contentJson);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NoteBlocksCompanion toCompanion(bool nullToAbsent) {
    return NoteBlocksCompanion(
      id: Value(id),
      noteId: Value(noteId),
      blockType: Value(blockType),
      contentText: contentText == null && nullToAbsent
          ? const Value.absent()
          : Value(contentText),
      contentJson: contentJson == null && nullToAbsent
          ? const Value.absent()
          : Value(contentJson),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory NoteBlock.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteBlock(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      blockType: serializer.fromJson<String>(json['blockType']),
      contentText: serializer.fromJson<String?>(json['contentText']),
      contentJson: serializer.fromJson<String?>(json['contentJson']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'blockType': serializer.toJson<String>(blockType),
      'contentText': serializer.toJson<String?>(contentText),
      'contentJson': serializer.toJson<String?>(contentJson),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NoteBlock copyWith({
    String? id,
    String? noteId,
    String? blockType,
    Value<String?> contentText = const Value.absent(),
    Value<String?> contentJson = const Value.absent(),
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => NoteBlock(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    blockType: blockType ?? this.blockType,
    contentText: contentText.present ? contentText.value : this.contentText,
    contentJson: contentJson.present ? contentJson.value : this.contentJson,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NoteBlock copyWithCompanion(NoteBlocksCompanion data) {
    return NoteBlock(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      blockType: data.blockType.present ? data.blockType.value : this.blockType,
      contentText: data.contentText.present
          ? data.contentText.value
          : this.contentText,
      contentJson: data.contentJson.present
          ? data.contentJson.value
          : this.contentJson,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteBlock(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('blockType: $blockType, ')
          ..write('contentText: $contentText, ')
          ..write('contentJson: $contentJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    blockType,
    contentText,
    contentJson,
    sortOrder,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteBlock &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.blockType == this.blockType &&
          other.contentText == this.contentText &&
          other.contentJson == this.contentJson &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NoteBlocksCompanion extends UpdateCompanion<NoteBlock> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String> blockType;
  final Value<String?> contentText;
  final Value<String?> contentJson;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const NoteBlocksCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.blockType = const Value.absent(),
    this.contentText = const Value.absent(),
    this.contentJson = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteBlocksCompanion.insert({
    required String id,
    required String noteId,
    this.blockType = const Value.absent(),
    this.contentText = const Value.absent(),
    this.contentJson = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<NoteBlock> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? blockType,
    Expression<String>? contentText,
    Expression<String>? contentJson,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (blockType != null) 'block_type': blockType,
      if (contentText != null) 'content_text': contentText,
      if (contentJson != null) 'content_json': contentJson,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteBlocksCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String>? blockType,
    Value<String?>? contentText,
    Value<String?>? contentJson,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return NoteBlocksCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      blockType: blockType ?? this.blockType,
      contentText: contentText ?? this.contentText,
      contentJson: contentJson ?? this.contentJson,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (blockType.present) {
      map['block_type'] = Variable<String>(blockType.value);
    }
    if (contentText.present) {
      map['content_text'] = Variable<String>(contentText.value);
    }
    if (contentJson.present) {
      map['content_json'] = Variable<String>(contentJson.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteBlocksCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('blockType: $blockType, ')
          ..write('contentText: $contentText, ')
          ..write('contentJson: $contentJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteAnchorsTable extends NoteAnchors
    with TableInfo<$NoteAnchorsTable, NoteAnchor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteAnchorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _anchorTypeMeta = const VerificationMeta(
    'anchorType',
  );
  @override
  late final GeneratedColumn<String> anchorType = GeneratedColumn<String>(
    'anchor_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageNumberMeta = const VerificationMeta(
    'pageNumber',
  );
  @override
  late final GeneratedColumn<int> pageNumber = GeneratedColumn<int>(
    'page_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _selectedTextMeta = const VerificationMeta(
    'selectedText',
  );
  @override
  late final GeneratedColumn<String> selectedText = GeneratedColumn<String>(
    'selected_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _textBeforeMeta = const VerificationMeta(
    'textBefore',
  );
  @override
  late final GeneratedColumn<String> textBefore = GeneratedColumn<String>(
    'text_before',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _textAfterMeta = const VerificationMeta(
    'textAfter',
  );
  @override
  late final GeneratedColumn<String> textAfter = GeneratedColumn<String>(
    'text_after',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _geometryJsonMeta = const VerificationMeta(
    'geometryJson',
  );
  @override
  late final GeneratedColumn<String> geometryJson = GeneratedColumn<String>(
    'geometry_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    documentId,
    anchorType,
    pageNumber,
    selectedText,
    textBefore,
    textAfter,
    geometryJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_anchors';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteAnchor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    }
    if (data.containsKey('anchor_type')) {
      context.handle(
        _anchorTypeMeta,
        anchorType.isAcceptableOrUnknown(data['anchor_type']!, _anchorTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_anchorTypeMeta);
    }
    if (data.containsKey('page_number')) {
      context.handle(
        _pageNumberMeta,
        pageNumber.isAcceptableOrUnknown(data['page_number']!, _pageNumberMeta),
      );
    }
    if (data.containsKey('selected_text')) {
      context.handle(
        _selectedTextMeta,
        selectedText.isAcceptableOrUnknown(
          data['selected_text']!,
          _selectedTextMeta,
        ),
      );
    }
    if (data.containsKey('text_before')) {
      context.handle(
        _textBeforeMeta,
        textBefore.isAcceptableOrUnknown(data['text_before']!, _textBeforeMeta),
      );
    }
    if (data.containsKey('text_after')) {
      context.handle(
        _textAfterMeta,
        textAfter.isAcceptableOrUnknown(data['text_after']!, _textAfterMeta),
      );
    }
    if (data.containsKey('geometry_json')) {
      context.handle(
        _geometryJsonMeta,
        geometryJson.isAcceptableOrUnknown(
          data['geometry_json']!,
          _geometryJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteAnchor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteAnchor(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      ),
      anchorType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}anchor_type'],
      )!,
      pageNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_number'],
      ),
      selectedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selected_text'],
      ),
      textBefore: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_before'],
      ),
      textAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_after'],
      ),
      geometryJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}geometry_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NoteAnchorsTable createAlias(String alias) {
    return $NoteAnchorsTable(attachedDatabase, alias);
  }
}

class NoteAnchor extends DataClass implements Insertable<NoteAnchor> {
  final String id;
  final String noteId;
  final String? documentId;

  /// Examples:
  /// document, page, textSelection, region, highlight, image, equation, table
  final String anchorType;
  final int? pageNumber;
  final String? selectedText;
  final String? textBefore;
  final String? textAfter;

  /// JSON-encoded PDF-space geometry.
  ///
  /// Example future shape:
  /// [
  ///   {"pageNumber": 3, "x": 72.4, "y": 412.8, "width": 315.2, "height": 14.1}
  /// ]
  final String? geometryJson;
  final DateTime createdAt;
  const NoteAnchor({
    required this.id,
    required this.noteId,
    this.documentId,
    required this.anchorType,
    this.pageNumber,
    this.selectedText,
    this.textBefore,
    this.textAfter,
    this.geometryJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    if (!nullToAbsent || documentId != null) {
      map['document_id'] = Variable<String>(documentId);
    }
    map['anchor_type'] = Variable<String>(anchorType);
    if (!nullToAbsent || pageNumber != null) {
      map['page_number'] = Variable<int>(pageNumber);
    }
    if (!nullToAbsent || selectedText != null) {
      map['selected_text'] = Variable<String>(selectedText);
    }
    if (!nullToAbsent || textBefore != null) {
      map['text_before'] = Variable<String>(textBefore);
    }
    if (!nullToAbsent || textAfter != null) {
      map['text_after'] = Variable<String>(textAfter);
    }
    if (!nullToAbsent || geometryJson != null) {
      map['geometry_json'] = Variable<String>(geometryJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NoteAnchorsCompanion toCompanion(bool nullToAbsent) {
    return NoteAnchorsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      documentId: documentId == null && nullToAbsent
          ? const Value.absent()
          : Value(documentId),
      anchorType: Value(anchorType),
      pageNumber: pageNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(pageNumber),
      selectedText: selectedText == null && nullToAbsent
          ? const Value.absent()
          : Value(selectedText),
      textBefore: textBefore == null && nullToAbsent
          ? const Value.absent()
          : Value(textBefore),
      textAfter: textAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(textAfter),
      geometryJson: geometryJson == null && nullToAbsent
          ? const Value.absent()
          : Value(geometryJson),
      createdAt: Value(createdAt),
    );
  }

  factory NoteAnchor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteAnchor(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      documentId: serializer.fromJson<String?>(json['documentId']),
      anchorType: serializer.fromJson<String>(json['anchorType']),
      pageNumber: serializer.fromJson<int?>(json['pageNumber']),
      selectedText: serializer.fromJson<String?>(json['selectedText']),
      textBefore: serializer.fromJson<String?>(json['textBefore']),
      textAfter: serializer.fromJson<String?>(json['textAfter']),
      geometryJson: serializer.fromJson<String?>(json['geometryJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'documentId': serializer.toJson<String?>(documentId),
      'anchorType': serializer.toJson<String>(anchorType),
      'pageNumber': serializer.toJson<int?>(pageNumber),
      'selectedText': serializer.toJson<String?>(selectedText),
      'textBefore': serializer.toJson<String?>(textBefore),
      'textAfter': serializer.toJson<String?>(textAfter),
      'geometryJson': serializer.toJson<String?>(geometryJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NoteAnchor copyWith({
    String? id,
    String? noteId,
    Value<String?> documentId = const Value.absent(),
    String? anchorType,
    Value<int?> pageNumber = const Value.absent(),
    Value<String?> selectedText = const Value.absent(),
    Value<String?> textBefore = const Value.absent(),
    Value<String?> textAfter = const Value.absent(),
    Value<String?> geometryJson = const Value.absent(),
    DateTime? createdAt,
  }) => NoteAnchor(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    documentId: documentId.present ? documentId.value : this.documentId,
    anchorType: anchorType ?? this.anchorType,
    pageNumber: pageNumber.present ? pageNumber.value : this.pageNumber,
    selectedText: selectedText.present ? selectedText.value : this.selectedText,
    textBefore: textBefore.present ? textBefore.value : this.textBefore,
    textAfter: textAfter.present ? textAfter.value : this.textAfter,
    geometryJson: geometryJson.present ? geometryJson.value : this.geometryJson,
    createdAt: createdAt ?? this.createdAt,
  );
  NoteAnchor copyWithCompanion(NoteAnchorsCompanion data) {
    return NoteAnchor(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      anchorType: data.anchorType.present
          ? data.anchorType.value
          : this.anchorType,
      pageNumber: data.pageNumber.present
          ? data.pageNumber.value
          : this.pageNumber,
      selectedText: data.selectedText.present
          ? data.selectedText.value
          : this.selectedText,
      textBefore: data.textBefore.present
          ? data.textBefore.value
          : this.textBefore,
      textAfter: data.textAfter.present ? data.textAfter.value : this.textAfter,
      geometryJson: data.geometryJson.present
          ? data.geometryJson.value
          : this.geometryJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteAnchor(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('documentId: $documentId, ')
          ..write('anchorType: $anchorType, ')
          ..write('pageNumber: $pageNumber, ')
          ..write('selectedText: $selectedText, ')
          ..write('textBefore: $textBefore, ')
          ..write('textAfter: $textAfter, ')
          ..write('geometryJson: $geometryJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    documentId,
    anchorType,
    pageNumber,
    selectedText,
    textBefore,
    textAfter,
    geometryJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteAnchor &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.documentId == this.documentId &&
          other.anchorType == this.anchorType &&
          other.pageNumber == this.pageNumber &&
          other.selectedText == this.selectedText &&
          other.textBefore == this.textBefore &&
          other.textAfter == this.textAfter &&
          other.geometryJson == this.geometryJson &&
          other.createdAt == this.createdAt);
}

class NoteAnchorsCompanion extends UpdateCompanion<NoteAnchor> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String?> documentId;
  final Value<String> anchorType;
  final Value<int?> pageNumber;
  final Value<String?> selectedText;
  final Value<String?> textBefore;
  final Value<String?> textAfter;
  final Value<String?> geometryJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const NoteAnchorsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.documentId = const Value.absent(),
    this.anchorType = const Value.absent(),
    this.pageNumber = const Value.absent(),
    this.selectedText = const Value.absent(),
    this.textBefore = const Value.absent(),
    this.textAfter = const Value.absent(),
    this.geometryJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteAnchorsCompanion.insert({
    required String id,
    required String noteId,
    this.documentId = const Value.absent(),
    required String anchorType,
    this.pageNumber = const Value.absent(),
    this.selectedText = const Value.absent(),
    this.textBefore = const Value.absent(),
    this.textAfter = const Value.absent(),
    this.geometryJson = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       anchorType = Value(anchorType),
       createdAt = Value(createdAt);
  static Insertable<NoteAnchor> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? documentId,
    Expression<String>? anchorType,
    Expression<int>? pageNumber,
    Expression<String>? selectedText,
    Expression<String>? textBefore,
    Expression<String>? textAfter,
    Expression<String>? geometryJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (documentId != null) 'document_id': documentId,
      if (anchorType != null) 'anchor_type': anchorType,
      if (pageNumber != null) 'page_number': pageNumber,
      if (selectedText != null) 'selected_text': selectedText,
      if (textBefore != null) 'text_before': textBefore,
      if (textAfter != null) 'text_after': textAfter,
      if (geometryJson != null) 'geometry_json': geometryJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteAnchorsCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String?>? documentId,
    Value<String>? anchorType,
    Value<int?>? pageNumber,
    Value<String?>? selectedText,
    Value<String?>? textBefore,
    Value<String?>? textAfter,
    Value<String?>? geometryJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return NoteAnchorsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      documentId: documentId ?? this.documentId,
      anchorType: anchorType ?? this.anchorType,
      pageNumber: pageNumber ?? this.pageNumber,
      selectedText: selectedText ?? this.selectedText,
      textBefore: textBefore ?? this.textBefore,
      textAfter: textAfter ?? this.textAfter,
      geometryJson: geometryJson ?? this.geometryJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (anchorType.present) {
      map['anchor_type'] = Variable<String>(anchorType.value);
    }
    if (pageNumber.present) {
      map['page_number'] = Variable<int>(pageNumber.value);
    }
    if (selectedText.present) {
      map['selected_text'] = Variable<String>(selectedText.value);
    }
    if (textBefore.present) {
      map['text_before'] = Variable<String>(textBefore.value);
    }
    if (textAfter.present) {
      map['text_after'] = Variable<String>(textAfter.value);
    }
    if (geometryJson.present) {
      map['geometry_json'] = Variable<String>(geometryJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteAnchorsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('documentId: $documentId, ')
          ..write('anchorType: $anchorType, ')
          ..write('pageNumber: $pageNumber, ')
          ..write('selectedText: $selectedText, ')
          ..write('textBefore: $textBefore, ')
          ..write('textAfter: $textAfter, ')
          ..write('geometryJson: $geometryJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PdfDocumentsTable pdfDocuments = $PdfDocumentsTable(this);
  late final $PdfSessionsTable pdfSessions = $PdfSessionsTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $DocumentTagsTable documentTags = $DocumentTagsTable(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $NoteBlocksTable noteBlocks = $NoteBlocksTable(this);
  late final $NoteAnchorsTable noteAnchors = $NoteAnchorsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pdfDocuments,
    pdfSessions,
    tags,
    documentTags,
    notes,
    noteBlocks,
    noteAnchors,
  ];
}

typedef $$PdfDocumentsTableCreateCompanionBuilder =
    PdfDocumentsCompanion Function({
      required String documentId,
      required String filePath,
      required String originalFileName,
      required String name,
      Value<String?> authors,
      Value<String?> subject,
      Value<String?> fieldOfStudy,
      Value<String?> isbn,
      Value<String?> doi,
      Value<String?> issn,
      Value<String?> arxivId,
      Value<String?> journal,
      Value<String?> publisher,
      Value<String?> keywords,
      required DateTime addedAt,
      Value<DateTime?> fileLastModifiedAt,
      Value<DateTime?> metadataLastEditedAt,
      Value<int> rowid,
    });
typedef $$PdfDocumentsTableUpdateCompanionBuilder =
    PdfDocumentsCompanion Function({
      Value<String> documentId,
      Value<String> filePath,
      Value<String> originalFileName,
      Value<String> name,
      Value<String?> authors,
      Value<String?> subject,
      Value<String?> fieldOfStudy,
      Value<String?> isbn,
      Value<String?> doi,
      Value<String?> issn,
      Value<String?> arxivId,
      Value<String?> journal,
      Value<String?> publisher,
      Value<String?> keywords,
      Value<DateTime> addedAt,
      Value<DateTime?> fileLastModifiedAt,
      Value<DateTime?> metadataLastEditedAt,
      Value<int> rowid,
    });

class $$PdfDocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $PdfDocumentsTable> {
  $$PdfDocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalFileName => $composableBuilder(
    column: $table.originalFileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authors => $composableBuilder(
    column: $table.authors,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldOfStudy => $composableBuilder(
    column: $table.fieldOfStudy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get isbn => $composableBuilder(
    column: $table.isbn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get doi => $composableBuilder(
    column: $table.doi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get issn => $composableBuilder(
    column: $table.issn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get arxivId => $composableBuilder(
    column: $table.arxivId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get journal => $composableBuilder(
    column: $table.journal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publisher => $composableBuilder(
    column: $table.publisher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keywords => $composableBuilder(
    column: $table.keywords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fileLastModifiedAt => $composableBuilder(
    column: $table.fileLastModifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get metadataLastEditedAt => $composableBuilder(
    column: $table.metadataLastEditedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PdfDocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $PdfDocumentsTable> {
  $$PdfDocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalFileName => $composableBuilder(
    column: $table.originalFileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authors => $composableBuilder(
    column: $table.authors,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldOfStudy => $composableBuilder(
    column: $table.fieldOfStudy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get isbn => $composableBuilder(
    column: $table.isbn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get doi => $composableBuilder(
    column: $table.doi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get issn => $composableBuilder(
    column: $table.issn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get arxivId => $composableBuilder(
    column: $table.arxivId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get journal => $composableBuilder(
    column: $table.journal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publisher => $composableBuilder(
    column: $table.publisher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keywords => $composableBuilder(
    column: $table.keywords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fileLastModifiedAt => $composableBuilder(
    column: $table.fileLastModifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get metadataLastEditedAt => $composableBuilder(
    column: $table.metadataLastEditedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PdfDocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PdfDocumentsTable> {
  $$PdfDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get originalFileName => $composableBuilder(
    column: $table.originalFileName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get authors =>
      $composableBuilder(column: $table.authors, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get fieldOfStudy => $composableBuilder(
    column: $table.fieldOfStudy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get isbn =>
      $composableBuilder(column: $table.isbn, builder: (column) => column);

  GeneratedColumn<String> get doi =>
      $composableBuilder(column: $table.doi, builder: (column) => column);

  GeneratedColumn<String> get issn =>
      $composableBuilder(column: $table.issn, builder: (column) => column);

  GeneratedColumn<String> get arxivId =>
      $composableBuilder(column: $table.arxivId, builder: (column) => column);

  GeneratedColumn<String> get journal =>
      $composableBuilder(column: $table.journal, builder: (column) => column);

  GeneratedColumn<String> get publisher =>
      $composableBuilder(column: $table.publisher, builder: (column) => column);

  GeneratedColumn<String> get keywords =>
      $composableBuilder(column: $table.keywords, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get fileLastModifiedAt => $composableBuilder(
    column: $table.fileLastModifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get metadataLastEditedAt => $composableBuilder(
    column: $table.metadataLastEditedAt,
    builder: (column) => column,
  );
}

class $$PdfDocumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PdfDocumentsTable,
          PdfDocument,
          $$PdfDocumentsTableFilterComposer,
          $$PdfDocumentsTableOrderingComposer,
          $$PdfDocumentsTableAnnotationComposer,
          $$PdfDocumentsTableCreateCompanionBuilder,
          $$PdfDocumentsTableUpdateCompanionBuilder,
          (
            PdfDocument,
            BaseReferences<_$AppDatabase, $PdfDocumentsTable, PdfDocument>,
          ),
          PdfDocument,
          PrefetchHooks Function()
        > {
  $$PdfDocumentsTableTableManager(_$AppDatabase db, $PdfDocumentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PdfDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PdfDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PdfDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> documentId = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String> originalFileName = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> authors = const Value.absent(),
                Value<String?> subject = const Value.absent(),
                Value<String?> fieldOfStudy = const Value.absent(),
                Value<String?> isbn = const Value.absent(),
                Value<String?> doi = const Value.absent(),
                Value<String?> issn = const Value.absent(),
                Value<String?> arxivId = const Value.absent(),
                Value<String?> journal = const Value.absent(),
                Value<String?> publisher = const Value.absent(),
                Value<String?> keywords = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<DateTime?> fileLastModifiedAt = const Value.absent(),
                Value<DateTime?> metadataLastEditedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PdfDocumentsCompanion(
                documentId: documentId,
                filePath: filePath,
                originalFileName: originalFileName,
                name: name,
                authors: authors,
                subject: subject,
                fieldOfStudy: fieldOfStudy,
                isbn: isbn,
                doi: doi,
                issn: issn,
                arxivId: arxivId,
                journal: journal,
                publisher: publisher,
                keywords: keywords,
                addedAt: addedAt,
                fileLastModifiedAt: fileLastModifiedAt,
                metadataLastEditedAt: metadataLastEditedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String documentId,
                required String filePath,
                required String originalFileName,
                required String name,
                Value<String?> authors = const Value.absent(),
                Value<String?> subject = const Value.absent(),
                Value<String?> fieldOfStudy = const Value.absent(),
                Value<String?> isbn = const Value.absent(),
                Value<String?> doi = const Value.absent(),
                Value<String?> issn = const Value.absent(),
                Value<String?> arxivId = const Value.absent(),
                Value<String?> journal = const Value.absent(),
                Value<String?> publisher = const Value.absent(),
                Value<String?> keywords = const Value.absent(),
                required DateTime addedAt,
                Value<DateTime?> fileLastModifiedAt = const Value.absent(),
                Value<DateTime?> metadataLastEditedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PdfDocumentsCompanion.insert(
                documentId: documentId,
                filePath: filePath,
                originalFileName: originalFileName,
                name: name,
                authors: authors,
                subject: subject,
                fieldOfStudy: fieldOfStudy,
                isbn: isbn,
                doi: doi,
                issn: issn,
                arxivId: arxivId,
                journal: journal,
                publisher: publisher,
                keywords: keywords,
                addedAt: addedAt,
                fileLastModifiedAt: fileLastModifiedAt,
                metadataLastEditedAt: metadataLastEditedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PdfDocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PdfDocumentsTable,
      PdfDocument,
      $$PdfDocumentsTableFilterComposer,
      $$PdfDocumentsTableOrderingComposer,
      $$PdfDocumentsTableAnnotationComposer,
      $$PdfDocumentsTableCreateCompanionBuilder,
      $$PdfDocumentsTableUpdateCompanionBuilder,
      (
        PdfDocument,
        BaseReferences<_$AppDatabase, $PdfDocumentsTable, PdfDocument>,
      ),
      PdfDocument,
      PrefetchHooks Function()
    >;
typedef $$PdfSessionsTableCreateCompanionBuilder =
    PdfSessionsCompanion Function({
      required String documentId,
      Value<int> pageNumber,
      Value<double> scrollX,
      Value<double> scrollY,
      Value<double> zoomLevel,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PdfSessionsTableUpdateCompanionBuilder =
    PdfSessionsCompanion Function({
      Value<String> documentId,
      Value<int> pageNumber,
      Value<double> scrollX,
      Value<double> scrollY,
      Value<double> zoomLevel,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PdfSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $PdfSessionsTable> {
  $$PdfSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageNumber => $composableBuilder(
    column: $table.pageNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get scrollX => $composableBuilder(
    column: $table.scrollX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get scrollY => $composableBuilder(
    column: $table.scrollY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get zoomLevel => $composableBuilder(
    column: $table.zoomLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PdfSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $PdfSessionsTable> {
  $$PdfSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageNumber => $composableBuilder(
    column: $table.pageNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get scrollX => $composableBuilder(
    column: $table.scrollX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get scrollY => $composableBuilder(
    column: $table.scrollY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get zoomLevel => $composableBuilder(
    column: $table.zoomLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PdfSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PdfSessionsTable> {
  $$PdfSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageNumber => $composableBuilder(
    column: $table.pageNumber,
    builder: (column) => column,
  );

  GeneratedColumn<double> get scrollX =>
      $composableBuilder(column: $table.scrollX, builder: (column) => column);

  GeneratedColumn<double> get scrollY =>
      $composableBuilder(column: $table.scrollY, builder: (column) => column);

  GeneratedColumn<double> get zoomLevel =>
      $composableBuilder(column: $table.zoomLevel, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PdfSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PdfSessionsTable,
          PdfSession,
          $$PdfSessionsTableFilterComposer,
          $$PdfSessionsTableOrderingComposer,
          $$PdfSessionsTableAnnotationComposer,
          $$PdfSessionsTableCreateCompanionBuilder,
          $$PdfSessionsTableUpdateCompanionBuilder,
          (
            PdfSession,
            BaseReferences<_$AppDatabase, $PdfSessionsTable, PdfSession>,
          ),
          PdfSession,
          PrefetchHooks Function()
        > {
  $$PdfSessionsTableTableManager(_$AppDatabase db, $PdfSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PdfSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PdfSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PdfSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> documentId = const Value.absent(),
                Value<int> pageNumber = const Value.absent(),
                Value<double> scrollX = const Value.absent(),
                Value<double> scrollY = const Value.absent(),
                Value<double> zoomLevel = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PdfSessionsCompanion(
                documentId: documentId,
                pageNumber: pageNumber,
                scrollX: scrollX,
                scrollY: scrollY,
                zoomLevel: zoomLevel,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String documentId,
                Value<int> pageNumber = const Value.absent(),
                Value<double> scrollX = const Value.absent(),
                Value<double> scrollY = const Value.absent(),
                Value<double> zoomLevel = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PdfSessionsCompanion.insert(
                documentId: documentId,
                pageNumber: pageNumber,
                scrollX: scrollX,
                scrollY: scrollY,
                zoomLevel: zoomLevel,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PdfSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PdfSessionsTable,
      PdfSession,
      $$PdfSessionsTableFilterComposer,
      $$PdfSessionsTableOrderingComposer,
      $$PdfSessionsTableAnnotationComposer,
      $$PdfSessionsTableCreateCompanionBuilder,
      $$PdfSessionsTableUpdateCompanionBuilder,
      (
        PdfSession,
        BaseReferences<_$AppDatabase, $PdfSessionsTable, PdfSession>,
      ),
      PdfSession,
      PrefetchHooks Function()
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({Value<int> id, required String name});
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({Value<int> id, Value<String> name});

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          Tag,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (Tag, BaseReferences<_$AppDatabase, $TagsTable, Tag>),
          Tag,
          PrefetchHooks Function()
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
              }) => TagsCompanion(id: id, name: name),
          createCompanionCallback:
              ({Value<int> id = const Value.absent(), required String name}) =>
                  TagsCompanion.insert(id: id, name: name),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      Tag,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (Tag, BaseReferences<_$AppDatabase, $TagsTable, Tag>),
      Tag,
      PrefetchHooks Function()
    >;
typedef $$DocumentTagsTableCreateCompanionBuilder =
    DocumentTagsCompanion Function({
      required String documentId,
      required int tagId,
      Value<int> rowid,
    });
typedef $$DocumentTagsTableUpdateCompanionBuilder =
    DocumentTagsCompanion Function({
      Value<String> documentId,
      Value<int> tagId,
      Value<int> rowid,
    });

class $$DocumentTagsTableFilterComposer
    extends Composer<_$AppDatabase, $DocumentTagsTable> {
  $$DocumentTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DocumentTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $DocumentTagsTable> {
  $$DocumentTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DocumentTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocumentTagsTable> {
  $$DocumentTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);
}

class $$DocumentTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DocumentTagsTable,
          DocumentTag,
          $$DocumentTagsTableFilterComposer,
          $$DocumentTagsTableOrderingComposer,
          $$DocumentTagsTableAnnotationComposer,
          $$DocumentTagsTableCreateCompanionBuilder,
          $$DocumentTagsTableUpdateCompanionBuilder,
          (
            DocumentTag,
            BaseReferences<_$AppDatabase, $DocumentTagsTable, DocumentTag>,
          ),
          DocumentTag,
          PrefetchHooks Function()
        > {
  $$DocumentTagsTableTableManager(_$AppDatabase db, $DocumentTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> documentId = const Value.absent(),
                Value<int> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentTagsCompanion(
                documentId: documentId,
                tagId: tagId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String documentId,
                required int tagId,
                Value<int> rowid = const Value.absent(),
              }) => DocumentTagsCompanion.insert(
                documentId: documentId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DocumentTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DocumentTagsTable,
      DocumentTag,
      $$DocumentTagsTableFilterComposer,
      $$DocumentTagsTableOrderingComposer,
      $$DocumentTagsTableAnnotationComposer,
      $$DocumentTagsTableCreateCompanionBuilder,
      $$DocumentTagsTableUpdateCompanionBuilder,
      (
        DocumentTag,
        BaseReferences<_$AppDatabase, $DocumentTagsTable, DocumentTag>,
      ),
      DocumentTag,
      PrefetchHooks Function()
    >;
typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      required String id,
      Value<String?> documentId,
      Value<String?> parentNoteId,
      Value<String?> title,
      Value<String> noteType,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> isArchived,
      Value<int> rowid,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<String> id,
      Value<String?> documentId,
      Value<String?> parentNoteId,
      Value<String?> title,
      Value<String> noteType,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isArchived,
      Value<int> rowid,
    });

class $$NotesTableFilterComposer extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentNoteId => $composableBuilder(
    column: $table.parentNoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteType => $composableBuilder(
    column: $table.noteType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentNoteId => $composableBuilder(
    column: $table.parentNoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteType => $composableBuilder(
    column: $table.noteType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentNoteId => $composableBuilder(
    column: $table.parentNoteId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get noteType =>
      $composableBuilder(column: $table.noteType, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotesTable,
          Note,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (Note, BaseReferences<_$AppDatabase, $NotesTable, Note>),
          Note,
          PrefetchHooks Function()
        > {
  $$NotesTableTableManager(_$AppDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> documentId = const Value.absent(),
                Value<String?> parentNoteId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String> noteType = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                documentId: documentId,
                parentNoteId: parentNoteId,
                title: title,
                noteType: noteType,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isArchived: isArchived,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> documentId = const Value.absent(),
                Value<String?> parentNoteId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String> noteType = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> isArchived = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                documentId: documentId,
                parentNoteId: parentNoteId,
                title: title,
                noteType: noteType,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isArchived: isArchived,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotesTable,
      Note,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (Note, BaseReferences<_$AppDatabase, $NotesTable, Note>),
      Note,
      PrefetchHooks Function()
    >;
typedef $$NoteBlocksTableCreateCompanionBuilder =
    NoteBlocksCompanion Function({
      required String id,
      required String noteId,
      Value<String> blockType,
      Value<String?> contentText,
      Value<String?> contentJson,
      Value<int> sortOrder,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$NoteBlocksTableUpdateCompanionBuilder =
    NoteBlocksCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<String> blockType,
      Value<String?> contentText,
      Value<String?> contentJson,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$NoteBlocksTableFilterComposer
    extends Composer<_$AppDatabase, $NoteBlocksTable> {
  $$NoteBlocksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockType => $composableBuilder(
    column: $table.blockType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentText => $composableBuilder(
    column: $table.contentText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteBlocksTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteBlocksTable> {
  $$NoteBlocksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockType => $composableBuilder(
    column: $table.blockType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentText => $composableBuilder(
    column: $table.contentText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteBlocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteBlocksTable> {
  $$NoteBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get blockType =>
      $composableBuilder(column: $table.blockType, builder: (column) => column);

  GeneratedColumn<String> get contentText => $composableBuilder(
    column: $table.contentText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NoteBlocksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteBlocksTable,
          NoteBlock,
          $$NoteBlocksTableFilterComposer,
          $$NoteBlocksTableOrderingComposer,
          $$NoteBlocksTableAnnotationComposer,
          $$NoteBlocksTableCreateCompanionBuilder,
          $$NoteBlocksTableUpdateCompanionBuilder,
          (
            NoteBlock,
            BaseReferences<_$AppDatabase, $NoteBlocksTable, NoteBlock>,
          ),
          NoteBlock,
          PrefetchHooks Function()
        > {
  $$NoteBlocksTableTableManager(_$AppDatabase db, $NoteBlocksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteBlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteBlocksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String> blockType = const Value.absent(),
                Value<String?> contentText = const Value.absent(),
                Value<String?> contentJson = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteBlocksCompanion(
                id: id,
                noteId: noteId,
                blockType: blockType,
                contentText: contentText,
                contentJson: contentJson,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                Value<String> blockType = const Value.absent(),
                Value<String?> contentText = const Value.absent(),
                Value<String?> contentJson = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => NoteBlocksCompanion.insert(
                id: id,
                noteId: noteId,
                blockType: blockType,
                contentText: contentText,
                contentJson: contentJson,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteBlocksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteBlocksTable,
      NoteBlock,
      $$NoteBlocksTableFilterComposer,
      $$NoteBlocksTableOrderingComposer,
      $$NoteBlocksTableAnnotationComposer,
      $$NoteBlocksTableCreateCompanionBuilder,
      $$NoteBlocksTableUpdateCompanionBuilder,
      (NoteBlock, BaseReferences<_$AppDatabase, $NoteBlocksTable, NoteBlock>),
      NoteBlock,
      PrefetchHooks Function()
    >;
typedef $$NoteAnchorsTableCreateCompanionBuilder =
    NoteAnchorsCompanion Function({
      required String id,
      required String noteId,
      Value<String?> documentId,
      required String anchorType,
      Value<int?> pageNumber,
      Value<String?> selectedText,
      Value<String?> textBefore,
      Value<String?> textAfter,
      Value<String?> geometryJson,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$NoteAnchorsTableUpdateCompanionBuilder =
    NoteAnchorsCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<String?> documentId,
      Value<String> anchorType,
      Value<int?> pageNumber,
      Value<String?> selectedText,
      Value<String?> textBefore,
      Value<String?> textAfter,
      Value<String?> geometryJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$NoteAnchorsTableFilterComposer
    extends Composer<_$AppDatabase, $NoteAnchorsTable> {
  $$NoteAnchorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get anchorType => $composableBuilder(
    column: $table.anchorType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageNumber => $composableBuilder(
    column: $table.pageNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textBefore => $composableBuilder(
    column: $table.textBefore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textAfter => $composableBuilder(
    column: $table.textAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get geometryJson => $composableBuilder(
    column: $table.geometryJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteAnchorsTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteAnchorsTable> {
  $$NoteAnchorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get anchorType => $composableBuilder(
    column: $table.anchorType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageNumber => $composableBuilder(
    column: $table.pageNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textBefore => $composableBuilder(
    column: $table.textBefore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textAfter => $composableBuilder(
    column: $table.textAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get geometryJson => $composableBuilder(
    column: $table.geometryJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteAnchorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteAnchorsTable> {
  $$NoteAnchorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get anchorType => $composableBuilder(
    column: $table.anchorType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageNumber => $composableBuilder(
    column: $table.pageNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get textBefore => $composableBuilder(
    column: $table.textBefore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get textAfter =>
      $composableBuilder(column: $table.textAfter, builder: (column) => column);

  GeneratedColumn<String> get geometryJson => $composableBuilder(
    column: $table.geometryJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$NoteAnchorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteAnchorsTable,
          NoteAnchor,
          $$NoteAnchorsTableFilterComposer,
          $$NoteAnchorsTableOrderingComposer,
          $$NoteAnchorsTableAnnotationComposer,
          $$NoteAnchorsTableCreateCompanionBuilder,
          $$NoteAnchorsTableUpdateCompanionBuilder,
          (
            NoteAnchor,
            BaseReferences<_$AppDatabase, $NoteAnchorsTable, NoteAnchor>,
          ),
          NoteAnchor,
          PrefetchHooks Function()
        > {
  $$NoteAnchorsTableTableManager(_$AppDatabase db, $NoteAnchorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteAnchorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteAnchorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteAnchorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String?> documentId = const Value.absent(),
                Value<String> anchorType = const Value.absent(),
                Value<int?> pageNumber = const Value.absent(),
                Value<String?> selectedText = const Value.absent(),
                Value<String?> textBefore = const Value.absent(),
                Value<String?> textAfter = const Value.absent(),
                Value<String?> geometryJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteAnchorsCompanion(
                id: id,
                noteId: noteId,
                documentId: documentId,
                anchorType: anchorType,
                pageNumber: pageNumber,
                selectedText: selectedText,
                textBefore: textBefore,
                textAfter: textAfter,
                geometryJson: geometryJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                Value<String?> documentId = const Value.absent(),
                required String anchorType,
                Value<int?> pageNumber = const Value.absent(),
                Value<String?> selectedText = const Value.absent(),
                Value<String?> textBefore = const Value.absent(),
                Value<String?> textAfter = const Value.absent(),
                Value<String?> geometryJson = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => NoteAnchorsCompanion.insert(
                id: id,
                noteId: noteId,
                documentId: documentId,
                anchorType: anchorType,
                pageNumber: pageNumber,
                selectedText: selectedText,
                textBefore: textBefore,
                textAfter: textAfter,
                geometryJson: geometryJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteAnchorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteAnchorsTable,
      NoteAnchor,
      $$NoteAnchorsTableFilterComposer,
      $$NoteAnchorsTableOrderingComposer,
      $$NoteAnchorsTableAnnotationComposer,
      $$NoteAnchorsTableCreateCompanionBuilder,
      $$NoteAnchorsTableUpdateCompanionBuilder,
      (
        NoteAnchor,
        BaseReferences<_$AppDatabase, $NoteAnchorsTable, NoteAnchor>,
      ),
      NoteAnchor,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PdfDocumentsTableTableManager get pdfDocuments =>
      $$PdfDocumentsTableTableManager(_db, _db.pdfDocuments);
  $$PdfSessionsTableTableManager get pdfSessions =>
      $$PdfSessionsTableTableManager(_db, _db.pdfSessions);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$DocumentTagsTableTableManager get documentTags =>
      $$DocumentTagsTableTableManager(_db, _db.documentTags);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$NoteBlocksTableTableManager get noteBlocks =>
      $$NoteBlocksTableTableManager(_db, _db.noteBlocks);
  $$NoteAnchorsTableTableManager get noteAnchors =>
      $$NoteAnchorsTableTableManager(_db, _db.noteAnchors);
}
