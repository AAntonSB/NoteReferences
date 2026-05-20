import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/reader_document_ref.dart';

class ReaderWorkspaceScreen extends StatefulWidget {
  final ReaderDocumentRef document;
  final String? subtitle;
  final Widget body;
  final Widget? contentsPane;
  final Widget? drawerContentsPane;
  final Widget? sidecar;
  final bool sidecarVisible;
  final ValueChanged<bool>? onSidecarVisibleChanged;
  final List<Widget> actions;
  final VoidCallback? onClose;

  const ReaderWorkspaceScreen({
    super.key,
    required this.document,
    required this.body,
    this.subtitle,
    this.contentsPane,
    this.drawerContentsPane,
    this.sidecar,
    this.sidecarVisible = false,
    this.onSidecarVisibleChanged,
    this.actions = const <Widget>[],
    this.onClose,
  });

  @override
  State<ReaderWorkspaceScreen> createState() => _ReaderWorkspaceScreenState();
}

class _ReaderWorkspaceScreenState extends State<ReaderWorkspaceScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool get _hasContents => widget.contentsPane != null || widget.drawerContentsPane != null;
  bool get _hasSidecar => widget.sidecar != null && widget.onSidecarVisibleChanged != null;

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _openContents() {
    _scaffoldKey.currentState?.openDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.subtitle?.trim();
    final actions = <Widget>[
      if (_hasContents)
        IconButton(
          tooltip: 'Contents',
          onPressed: _openContents,
          icon: const Icon(Icons.list_alt_rounded),
        ),
      if (_hasSidecar)
        IconButton(
          tooltip: widget.sidecarVisible ? 'Hide sidecar' : 'Show sidecar',
          onPressed: () => widget.onSidecarVisibleChanged!(!widget.sidecarVisible),
          icon: Icon(
            widget.sidecarVisible ? Icons.view_sidebar_rounded : Icons.view_sidebar_outlined,
          ),
        ),
      ...widget.actions,
    ];

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close reader',
          onPressed: _close,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.document.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle != null && subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        actions: actions,
      ),
      drawer: _hasContents
          ? Drawer(
              width: 360,
              child: widget.drawerContentsPane ?? widget.contentsPane!,
            )
          : null,
      body: _ReaderWorkspaceBody(
        body: widget.body,
        contentsPane: widget.contentsPane,
        sidecar: widget.sidecarVisible ? widget.sidecar : null,
      ),
    );
  }
}

class _ReaderWorkspaceBody extends StatelessWidget {
  final Widget body;
  final Widget? contentsPane;
  final Widget? sidecar;

  const _ReaderWorkspaceBody({
    required this.body,
    required this.contentsPane,
    required this.sidecar,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showContentsInline = contentsPane != null && constraints.maxWidth >= 1120;
        final readerWithContents = showContentsInline
            ? Row(
                children: [
                  SizedBox(width: 340, child: contentsPane!),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              )
            : body;

        final sidecar = this.sidecar;
        if (sidecar == null) return readerWithContents;

        if (constraints.maxWidth >= 980) {
          return Row(
            children: [
              Expanded(child: readerWithContents),
              const VerticalDivider(width: 1),
              SizedBox(width: 370, child: sidecar),
            ],
          );
        }

        return Column(
          children: [
            Expanded(child: readerWithContents),
            const Divider(height: 1),
            SizedBox(
              height: math.min(360.0, math.max(240.0, constraints.maxHeight * 0.42)),
              child: sidecar,
            ),
          ],
        );
      },
    );
  }
}
