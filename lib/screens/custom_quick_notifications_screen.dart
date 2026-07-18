import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/custom_quick_notification_template.dart';
import '../providers/app_state.dart';

class CustomQuickNotificationsScreen extends StatefulWidget {
  const CustomQuickNotificationsScreen({super.key});

  @override
  State<CustomQuickNotificationsScreen> createState() =>
      _CustomQuickNotificationsScreenState();
}

class _CustomQuickNotificationsScreenState
    extends State<CustomQuickNotificationsScreen> {
  final _labelController = TextEditingController();
  final _messageController = TextEditingController();
  final _searchController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final List<_IconChoice> _iconChoices = const [
    _IconChoice(Icons.schedule, 'Schedule'),
    _IconChoice(Icons.chat_bubble_outline, 'Chat'),
    _IconChoice(Icons.shield_outlined, 'Shield'),
    _IconChoice(Icons.priority_high, 'Priority'),
    _IconChoice(Icons.location_searching, 'Location'),
    _IconChoice(Icons.flight_takeoff, 'Air traffic'),
    _IconChoice(Icons.notifications_active_outlined, 'Alert'),
  ];

  final List<Color> _accentChoices = const [
    Colors.lightBlueAccent,
    Colors.greenAccent,
    Colors.amberAccent,
    Colors.orangeAccent,
    Colors.redAccent,
    Colors.purpleAccent,
    Colors.tealAccent,
  ];

  IconData _selectedIcon = Icons.chat_bubble_outline;
  Color _selectedAccent = Colors.lightBlueAccent;
  bool _selectedExplicit = false;
  _TemplateFilter _filter = _TemplateFilter.all;

  @override
  void dispose() {
    _labelController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final templates =
        _filteredTemplates(appState.customQuickNotificationTemplates);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Quick notifications'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Create'),
              Tab(text: 'Manage'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildCreateTab(appState),
            _buildManageTab(appState, templates),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateTab(AppState appState) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Create a reusable quick message for selected members.',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _labelController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'ETA?',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a label'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText: 'What is your ETA?',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a message'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<IconData>(
                initialValue: _selectedIcon,
                decoration: const InputDecoration(labelText: 'Icon'),
                items: _iconChoices
                    .map(
                      (choice) => DropdownMenuItem(
                        value: choice.icon,
                        child: Row(
                          children: [
                            Icon(choice.icon, size: 18),
                            const SizedBox(width: 8),
                            Text(choice.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedIcon = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Accent color',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _accentChoices
                    .map(
                      (color) => GestureDetector(
                        onTap: () => setState(() => _selectedAccent = color),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedAccent == color
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade400,
                              width: _selectedAccent == color ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Explicit message'),
                subtitle: const Text(
                    'Hide it when explicit quick actions are disabled.'),
                value: _selectedExplicit,
                onChanged: (value) => setState(() => _selectedExplicit = value),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _saveTemplate(appState),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save quick notification'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManageTab(
    AppState appState,
    List<CustomQuickNotificationTemplate> templates,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Search templates',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _filter == _TemplateFilter.all,
              onSelected: (_) => setState(() => _filter = _TemplateFilter.all),
            ),
            ChoiceChip(
              label: const Text('Non-explicit'),
              selected: _filter == _TemplateFilter.nonExplicit,
              onSelected: (_) =>
                  setState(() => _filter = _TemplateFilter.nonExplicit),
            ),
            ChoiceChip(
              label: const Text('Explicit'),
              selected: _filter == _TemplateFilter.explicit,
              onSelected: (_) =>
                  setState(() => _filter = _TemplateFilter.explicit),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (templates.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Center(
              child: Text('No custom quick notifications yet.'),
            ),
          )
        else
          ...templates.map(
            (template) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: template.accentColor.withValues(alpha: 0.22),
                  child: Icon(template.icon, color: template.accentColor),
                ),
                title: Text(template.label),
                subtitle: Text(
                  template.messageTemplate,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (template.isExplicit)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Chip(label: Text('Explicit')),
                      ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await appState.removeCustomQuickNotificationTemplate(
                          template.id,
                        );
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text('Deleted ${template.label}')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<CustomQuickNotificationTemplate> _filteredTemplates(
    List<CustomQuickNotificationTemplate> templates,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    return templates.where((template) {
      final matchesSearch = query.isEmpty ||
          template.label.toLowerCase().contains(query) ||
          template.messageTemplate.toLowerCase().contains(query);
      final matchesFilter = switch (_filter) {
        _TemplateFilter.all => true,
        _TemplateFilter.nonExplicit => !template.isExplicit,
        _TemplateFilter.explicit => template.isExplicit,
      };
      return matchesSearch && matchesFilter;
    }).toList();
  }

  Future<void> _saveTemplate(AppState appState) async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;
    final messenger = ScaffoldMessenger.of(context);

    final template = CustomQuickNotificationTemplate(
      id: const Uuid().v4(),
      label: _labelController.text.trim(),
      messageTemplate: _messageController.text.trim(),
      iconKey: CustomQuickNotificationTemplate.keyForIcon(_selectedIcon),
      accentColorArgb: _selectedAccent.toARGB32(),
      isExplicit: _selectedExplicit,
    );

    await appState.addCustomQuickNotificationTemplate(template);
    _labelController.clear();
    _messageController.clear();
    setState(() {
      _selectedIcon = Icons.chat_bubble_outline;
      _selectedAccent = Colors.lightBlueAccent;
      _selectedExplicit = false;
    });

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Saved ${template.label}')),
    );
  }
}

enum _TemplateFilter { all, nonExplicit, explicit }

class _IconChoice {
  final IconData icon;
  final String label;

  const _IconChoice(this.icon, this.label);
}
