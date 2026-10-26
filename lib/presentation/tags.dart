import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../application/controller.dart';
import '../domain/tag.dart';

/// Only untouched built-in names are UI resources. Renamed/custom tags are user data.
String tagName(BuildContext context, Tag tag) {
  final original = defaultTags.where((value) => value.id == tag.id).firstOrNull;
  if (original == null || original.name != tag.name) return tag.name;
  const names = [
    'Work',
    'Study',
    'Training',
    'Personal',
    'Home',
    'Health',
    'Leisure',
    'Other',
  ];
  return context.strings.text(names[defaultTags.indexOf(original)]);
}

String tagNames(
  BuildContext context,
  List<String> ids,
  List<Tag> catalogue,
) => catalogue
    .where((t) => ids.contains(t.id))
    .map(
      (t) =>
          '${tagName(context, t)}${t.archived ? context.strings.text(' (retired)') : ''}',
    )
    .join(', ');

class TagChips extends StatelessWidget {
  final List<String> ids;
  final List<Tag> catalogue;
  const TagChips(this.ids, this.catalogue, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final id in ids)
        for (final tag in catalogue.where((t) => t.id == id))
          Container(
            padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Color(tag.color),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${tagName(context, tag)}${tag.archived ? context.strings.text(' · retired') : ''}',
              style: TextStyle(
                color: Color(tag.color).computeLuminance() > .4
                    ? Color(0xff202530)
                    : Colors.white,
                fontSize: 11,
              ),
            ),
          ),
    ],
  );
}

/// One marker for compact calendar cells, with all names available on hover.
class TagMarker extends StatelessWidget {
  final List<String> ids;
  final List<Tag> catalogue;
  const TagMarker(this.ids, this.catalogue, {super.key});
  @override
  Widget build(BuildContext context) {
    final tags = [for (final id in ids) ...catalogue.where((t) => t.id == id)];
    if (tags.isEmpty) return SizedBox.shrink();
    return Tooltip(
      message: tagNames(context, ids, catalogue),
      child: Semantics(
        label: context.strings.text('Tags: {0}', [
          tagNames(context, ids, catalogue),
        ]),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Color(tags.first.color),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            if (tags.length > 1)
              Padding(
                padding: EdgeInsets.only(left: 2),
                child: Text(
                  '+${tags.length - 1}',
                  style: TextStyle(fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<Tag?> editTag(
  BuildContext context,
  CalendarController c, {
  Tag? tag,
  String initialName = '',
}) => showDialog<Tag>(
  context: context,
  builder: (_) => _TagEditor(controller: c, tag: tag, initialName: initialName),
);

class _TagEditor extends StatefulWidget {
  final CalendarController controller;
  final Tag? tag;
  final String initialName;
  const _TagEditor({
    required this.controller,
    this.tag,
    required this.initialName,
  });
  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  late final name = TextEditingController(
    text: widget.tag == null
        ? widget.initialName
        : tagName(context, widget.tag!),
  );
  late int color = widget.tag?.color ?? tagPalette.first;
  String? error;
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.tag == null
          ? context.strings.text('New tag')
          : context.strings.text('Edit tag'),
    ),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: context.strings.text('Tag name'),
            ),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final value in tagPalette)
                IconButton(
                  tooltip: context.strings.text('Color {0}', [
                    tagPalette.indexOf(value) + 1,
                  ]),
                  style: IconButton.styleFrom(
                    backgroundColor: Color(value),
                    foregroundColor: Color(0xff202530),
                  ),
                  onPressed: saving
                      ? null
                      : () => setState(() => color = value),
                  icon: Icon(
                    value == color ? Icons.check : Icons.circle_outlined,
                  ),
                ),
            ],
          ),
          if (error != null)
            Text(
              context.strings.error(error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: Text(context.strings.text('Cancel')),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                setState(() {
                  saving = true;
                  error = null;
                });
                final tag = Tag(
                  id: widget.tag?.id ?? Uuid().v4(),
                  name:
                      widget.tag != null &&
                          name.text.trim() == tagName(context, widget.tag!)
                      ? widget.tag!.name
                      : name.text.trim(),
                  color: color,
                );
                final duplicate = widget.controller.tags.any(
                  (existing) =>
                      existing.id != tag.id &&
                      tagName(context, existing).trim().toLowerCase() ==
                          name.text.trim().toLowerCase(),
                );
                if (duplicate) {
                  setState(() {
                    saving = false;
                    error = 'A tag with this name already exists.';
                  });
                  return;
                }
                await widget.controller.run(
                  () => widget.controller.service.repository.saveTag(tag),
                );
                if (!context.mounted) return;
                if (widget.controller.error != null) {
                  setState(() {
                    saving = false;
                    error = widget.controller.error;
                  });
                } else {
                  Navigator.pop(context, tag);
                }
              },
        child: Text(
          saving
              ? context.strings.text('Saving…')
              : context.strings.text('Save tag'),
        ),
      ),
    ],
  );
}

class TagSelector extends StatefulWidget {
  final CalendarController controller;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  const TagSelector({
    super.key,
    required this.controller,
    required this.selected,
    required this.onChanged,
  });
  @override
  State<TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends State<TagSelector> {
  Future<void> choose() async {
    final selected = [...widget.selected];
    var searchGeneration = 0;
    var search = '';
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(context.strings.text('Tags')),
          content: SizedBox(
            width: 400,
            height: 300,
            child: Column(
              children: [
                TextField(
                  key: ValueKey(searchGeneration),
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: context.strings.text('Search tags'),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => update(() => search = v),
                ),
                SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final tag in widget.controller.tags.where(
                        (t) =>
                            (!t.archived || selected.contains(t.id)) &&
                            tagName(context, t).toLowerCase().contains(
                              search.trim().toLowerCase(),
                            ),
                      ))
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: TagChips([tag.id], widget.controller.tags),
                          value: selected.contains(tag.id),
                          onChanged: (v) => update(() {
                            v! ? selected.add(tag.id) : selected.remove(tag.id);
                          }),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  icon: Icon(Icons.add),
                  label: Text(context.strings.text('Create tag')),
                  onPressed: () async {
                    final tag = await editTag(
                      context,
                      widget.controller,
                      initialName: search.trim(),
                    );
                    if (tag != null && context.mounted) {
                      update(() {
                        selected.add(tag.id);
                        search = '';
                        searchGeneration++;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.strings.text('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: Text(context.strings.text('Apply')),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(context.strings.text('Tags (optional)')),
          Spacer(),
          TextButton.icon(
            onPressed: choose,
            icon: Icon(Icons.label_outline, size: 18),
            label: Text(context.strings.text('Choose')),
          ),
        ],
      ),
      if (widget.selected.isNotEmpty)
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final id in widget.selected)
              InputChip(
                label: TagChips([id], widget.controller.tags),
                onDeleted: () =>
                    widget.onChanged([...widget.selected]..remove(id)),
              ),
          ],
        ),
    ],
  );
}

class TagSettings extends StatelessWidget {
  final CalendarController controller;
  const TagSettings(this.controller, {super.key});
  Future<void> remove(BuildContext context, Tag tag) async {
    final used = await controller.service.repository.tagInUse(tag.id);
    if (!context.mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.strings.text('Retire “{0}”?', [tagName(context, tag)])),
        content: Text(
          used
              ? context.strings.text(
                  'This tag is used by activities or their history. All associations and data will be kept. It will no longer be offered for new activities.',
                )
              : context.strings.text(
                  'It will no longer be offered for new activities. Its name will remain reserved.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(context.strings.text('Retire')),
          ),
        ],
      ),
    );
    if (yes == true) {
      await controller.run(
        () => controller.service.repository.archiveTag(tag.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            context.strings.text('Tags'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(width: 12),
          TextButton.icon(
            onPressed: controller.loading
                ? null
                : () => editTag(context, controller),
            icon: Icon(Icons.add),
            label: Text(context.strings.text('New tag')),
          ),
        ],
      ),
      Text(
        context.strings.text(
          'Organize activities without changing their schedule.',
        ),
      ),
      SizedBox(height: 8),
      for (final tag in controller.tags.where((t) => !t.archived))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: TagChips([tag.id], controller.tags),
          subtitle: tag.predefined
              ? Text(context.strings.text('Built-in'))
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: context.strings.text('Edit {0}', [tagName(context, tag)]),
                icon: Icon(Icons.edit_outlined),
                onPressed: controller.loading
                    ? null
                    : () => editTag(context, controller, tag: tag),
              ),
              if (!tag.predefined)
                IconButton(
                  tooltip: context.strings.text('Retire {0}', [tagName(context, tag)]),
                  icon: Icon(Icons.delete_outline),
                  onPressed: controller.loading
                      ? null
                      : () => remove(context, tag),
                ),
            ],
          ),
        ),
    ],
  );
}
