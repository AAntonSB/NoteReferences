import 'dart:async';

import 'package:flutter/material.dart';

import 'text_system_reference_action_controller.dart';
import 'text_system_reference_action_models.dart';
import 'text_system_reference_action_repository.dart';
import '../citations/text_system_citation.dart';

Future<TextSystemReferenceActionResult?> showTextSystemReferenceActionPicker({
  required BuildContext context,
  required String selectedText,
  required TextSystemReferenceActionRepository repository,
  TextSystemReferenceActionType initialActionType = TextSystemReferenceActionType.source,
  TextSystemCitationSettings citationSettings = const TextSystemCitationSettings(),
}) {
  return showModalBottomSheet<TextSystemReferenceActionResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      return TextSystemReferenceActionPicker(
        selectedText: selectedText,
        repository: repository,
        initialActionType: initialActionType,
        citationSettings: citationSettings,
      );
    },
  );
}

class TextSystemReferenceActionPicker extends StatefulWidget {
  const TextSystemReferenceActionPicker({
    super.key,
    required this.selectedText,
    required this.repository,
    this.initialActionType = TextSystemReferenceActionType.source,
    this.citationSettings = const TextSystemCitationSettings(),
  });

  final String selectedText;
  final TextSystemReferenceActionRepository repository;
  final TextSystemReferenceActionType initialActionType;
  final TextSystemCitationSettings citationSettings;

  @override
  State<TextSystemReferenceActionPicker> createState() => _TextSystemReferenceActionPickerState();
}

class _TextSystemReferenceActionPickerState
    extends State<TextSystemReferenceActionPicker> {
  late final TextSystemReferenceActionController _controller;
  late final TextEditingController _searchController;
  final TextEditingController _uriController = TextEditingController();
  final TextEditingController _citationKeyController = TextEditingController();
  final TextEditingController _citationAuthorsController = TextEditingController();
  final TextEditingController _citationYearController = TextEditingController();
  final TextEditingController _citationTitleController = TextEditingController();
  final TextEditingController _citationContainerController = TextEditingController();
  final TextEditingController _citationPublisherController = TextEditingController();
  final TextEditingController _citationDoiController = TextEditingController();
  final TextEditingController _citationLocatorController = TextEditingController();
  late TextSystemCitationInlineMode _citationInlineMode;

  @override
  void initState() {
    super.initState();
    _citationInlineMode = widget.citationSettings.inlineMode;
    _controller = TextSystemReferenceActionController(
      repository: widget.repository,
      selectedText: widget.selectedText,
      initialActionType: widget.initialActionType,
    );
    _searchController = TextEditingController(text: widget.selectedText.trim());
    _controller.addListener(_handleControllerChanged);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    _searchController.dispose();
    _uriController.dispose();
    _citationKeyController.dispose();
    _citationAuthorsController.dispose();
    _citationYearController.dispose();
    _citationTitleController.dispose();
    _citationContainerController.dispose();
    _citationPublisherController.dispose();
    _citationDoiController.dispose();
    _citationLocatorController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: _Header(selectedText: widget.selectedText),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ActionTypeChips(
                value: _controller.actionType,
                onChanged: _controller.setActionType,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search or create ${_controller.actionType.label.toLowerCase()}',
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.search,
                onChanged: _controller.updateQuery,
                onSubmitted: (_) => _controller.searchNow(),
              ),
            ),
            if (_controller.actionType == TextSystemReferenceActionType.link ||
                _controller.actionType == TextSystemReferenceActionType.source)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: TextField(
                  controller: _uriController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.language),
                    hintText: 'Optional URL or source URI',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
              ),
            if (_controller.actionType == TextSystemReferenceActionType.citation)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _CitationMetadataFields(
                  authorsController: _citationAuthorsController,
                  yearController: _citationYearController,
                  titleController: _citationTitleController,
                  containerController: _citationContainerController,
                  publisherController: _citationPublisherController,
                  doiController: _citationDoiController,
                  locatorController: _citationLocatorController,
                  citationKeyController: _citationKeyController,
                  inlineMode: _citationInlineMode,
                  onInlineModeChanged: (value) {
                    if (value == null) return;
                    setState(() => _citationInlineMode = value);
                  },
                ),
              ),
            const SizedBox(height: 8),
            if (_controller.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Could not load references: ${_controller.error}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                children: <Widget>[
                  if (_controller.recent.isNotEmpty) ...<Widget>[
                    _SectionLabel('Recent ${_controller.actionType.label.toLowerCase()}s'),
                    ..._controller.recent.map(_buildTargetTile),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _SectionLabel(
                          _controller.query.trim().isEmpty ? 'All matches' : 'Matches',
                        ),
                      ),
                      if (_controller.isLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  if (!_controller.isLoading && _controller.results.isEmpty)
                    _EmptyResults(actionType: _controller.actionType),
                  ..._controller.results.map(_buildTargetTile),
                  const Divider(height: 24),
                  _CreateReferenceTile(
                    actionType: _controller.actionType,
                    query: _controller.query,
                    selectedText: _controller.selectedText,
                    onPressed: _createAndReturn,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetTile(TextSystemReferenceTarget target) {
    return ListTile(
      leading: _ReferenceKindIcon(kind: target.kind),
      title: Text(target.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: target.subtitle == null
          ? Text(target.kind.label)
          : Text(target.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.keyboard_return),
      onTap: () {
        Navigator.of(context).pop(_controller.composeResult(target));
      },
    );
  }

  Future<void> _createAndReturn() async {
    final uri = Uri.tryParse(_uriController.text.trim());
    final citationKey = _citationKeyController.text.trim();
    final isCitation = _controller.actionType == TextSystemReferenceActionType.citation;
    final authors = _citationAuthorsController.text
        .split(RegExp(r'\s*;\s*|\s+and\s+|\s+&\s+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final citationTitle = _citationTitleController.text.trim();
    final year = _citationYearController.text.trim();
    final displayLabel = isCitation && (authors.isNotEmpty || year.isNotEmpty)
        ? '${authors.isEmpty ? (citationTitle.isEmpty ? _controller.query.trim() : citationTitle) : authors.join(' & ')}${year.isEmpty ? '' : ' ($year)'}'
        : null;
    final metadata = <String, Object?>{
      if (isCitation) 'citationInlineMode': _citationInlineMode.id,
      if (isCitation && authors.isNotEmpty) 'authors': authors,
      if (isCitation && year.isNotEmpty) 'year': year,
      if (isCitation && citationTitle.isNotEmpty) 'title': citationTitle,
      if (isCitation && _citationContainerController.text.trim().isNotEmpty)
        'containerTitle': _citationContainerController.text.trim(),
      if (isCitation && _citationPublisherController.text.trim().isNotEmpty)
        'publisher': _citationPublisherController.text.trim(),
      if (isCitation && _citationDoiController.text.trim().isNotEmpty)
        'doi': _citationDoiController.text.trim(),
      if (isCitation && _citationLocatorController.text.trim().isNotEmpty)
        'locator': _citationLocatorController.text.trim(),
      if (uri?.hasScheme == true) 'url': uri.toString(),
    };
    final result = await _controller.createAndSelect(
      label: displayLabel,
      uri: uri?.hasScheme == true ? uri : null,
      citationKey: citationKey.isEmpty ? null : citationKey,
      metadata: metadata,
    );
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.selectedText});

  final String selectedText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = selectedText.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Reference selected text', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        if (trimmed.isEmpty)
          Text(
            'No text is selected. The chosen reference label will be inserted at the caret.',
            style: theme.textTheme.bodySmall,
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Text(
              trimmed,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}


class _CitationMetadataFields extends StatelessWidget {
  const _CitationMetadataFields({
    required this.authorsController,
    required this.yearController,
    required this.titleController,
    required this.containerController,
    required this.publisherController,
    required this.doiController,
    required this.locatorController,
    required this.citationKeyController,
    required this.inlineMode,
    required this.onInlineModeChanged,
  });

  final TextEditingController authorsController;
  final TextEditingController yearController;
  final TextEditingController titleController;
  final TextEditingController containerController;
  final TextEditingController publisherController;
  final TextEditingController doiController;
  final TextEditingController locatorController;
  final TextEditingController citationKeyController;
  final TextSystemCitationInlineMode inlineMode;
  final ValueChanged<TextSystemCitationInlineMode?> onInlineModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: TextField(
                controller: authorsController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline),
                  hintText: 'Authors, e.g. Smith; Jones',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: yearController,
                decoration: const InputDecoration(
                  hintText: 'Year',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: titleController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.title),
            hintText: 'Source title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: containerController,
                decoration: const InputDecoration(
                  hintText: 'Journal/book/site',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: publisherController,
                decoration: const InputDecoration(
                  hintText: 'Publisher',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: locatorController,
                decoration: const InputDecoration(
                  hintText: 'Page/locator, e.g. 42',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<TextSystemCitationInlineMode>(
                value: inlineMode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Inline mode',
                ),
                items: TextSystemCitationInlineMode.values
                    .map(
                      (mode) => DropdownMenuItem<TextSystemCitationInlineMode>(
                        value: mode,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: onInlineModeChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: citationKeyController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.tag),
                  hintText: 'Citation key, e.g. smith2020',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: doiController,
                decoration: const InputDecoration(
                  hintText: 'DOI',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionTypeChips extends StatelessWidget {
  const _ActionTypeChips({required this.value, required this.onChanged});

  final TextSystemReferenceActionType value;
  final ValueChanged<TextSystemReferenceActionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: TextSystemReferenceActionType.values.map((type) {
        return ChoiceChip(
          label: Text(type.label),
          selected: value == type,
          onSelected: (_) => onChanged(type),
        );
      }).toList(growable: false),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.actionType});

  final TextSystemReferenceActionType actionType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'No existing ${actionType.label.toLowerCase()} found. Create one below.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _CreateReferenceTile extends StatelessWidget {
  const _CreateReferenceTile({
    required this.actionType,
    required this.query,
    required this.selectedText,
    required this.onPressed,
  });

  final TextSystemReferenceActionType actionType;
  final String query;
  final String selectedText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = query.trim().isNotEmpty
        ? query.trim()
        : selectedText.trim().isNotEmpty
            ? selectedText.trim()
            : actionType.label;
    return ListTile(
      leading: const Icon(Icons.add_circle_outline),
      title: Text('${actionType.verbLabel}: $label'),
      subtitle: const Text('Create a new reference target and apply it to the document.'),
      onTap: onPressed,
    );
  }
}

class _ReferenceKindIcon extends StatelessWidget {
  const _ReferenceKindIcon({required this.kind});

  final TextSystemReferenceTargetKind kind;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case TextSystemReferenceTargetKind.citation:
        return const Icon(Icons.format_quote);
      case TextSystemReferenceTargetKind.source:
        return const Icon(Icons.picture_as_pdf_outlined);
      case TextSystemReferenceTargetKind.document:
        return const Icon(Icons.description_outlined);
      case TextSystemReferenceTargetKind.project:
        return const Icon(Icons.folder_open);
      case TextSystemReferenceTargetKind.todo:
        return const Icon(Icons.check_circle_outline);
      case TextSystemReferenceTargetKind.link:
        return const Icon(Icons.link);
      case TextSystemReferenceTargetKind.figure:
        return const Icon(Icons.image_outlined);
      case TextSystemReferenceTargetKind.table:
        return const Icon(Icons.table_chart_outlined);
      case TextSystemReferenceTargetKind.unknown:
        return const Icon(Icons.bookmark_border);
    }
  }
}
