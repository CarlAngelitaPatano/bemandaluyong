import 'package:flutter/material.dart';

import 'heritage.dart'; // kChurches, ChurchDetailPage
import 'city_content.dart'; // CityItem, CityDetailPage, kServices, kEvents
import 'attractions.dart'; // kAttractions
import 'theme.dart';

// ===========================================================================
// Global search across churches, services, events, and attractions.
// (Live News is excluded because it's fetched fresh from the web.)
// ===========================================================================

class _Hit {
  final IconData icon;
  final String title;
  final String category;
  final Widget Function() page;
  _Hit(this.icon, this.title, this.category, this.page);
}

class AppSearchDelegate extends SearchDelegate<String?> {
  @override
  String? get searchFieldLabel => 'Search churches, services, events…';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear),
            onPressed: () {
              query = '';
              showSuggestions(context);
            },
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  List<_Hit> _search(String query) {
    final q = query.trim().toLowerCase();
    final hits = <_Hit>[];
    if (q.isEmpty) return hits;

    for (final c in kChurches) {
      final hay =
          '${c.name} ${c.era} ${c.location} ${c.nearest} ${c.description}'
              .toLowerCase();
      if (hay.contains(q)) {
        hits.add(_Hit(Icons.church_outlined, c.name, 'Heritage church',
            () => ChurchDetailPage(church: c)));
      }
    }

    void addItems(List<CityItem> items, String label) {
      for (final it in items) {
        final hay = '${it.title} ${it.tag} ${it.meta} ${it.body}'.toLowerCase();
        if (hay.contains(q)) {
          hits.add(_Hit(it.icon, it.title, label, () => CityDetailPage(item: it)));
        }
      }
    }

    addItems(kServices, 'Service');
    addItems(kEvents, 'Event');
    addItems(kAttractions, 'Attraction');
    return hits;
  }

  Widget _buildList(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (query.trim().isEmpty) {
      return _CenterHint(
        icon: Icons.search,
        message: 'Search for churches, services, events, and attractions.',
      );
    }

    final hits = _search(query);
    if (hits.isEmpty) {
      return _CenterHint(
        icon: Icons.search_off,
        message: 'No results for “${query.trim()}”.',
      );
    }

    return ListView.separated(
      itemCount: hits.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final h = hits[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: colors.primaryContainer,
            child: Icon(h.icon, color: colors.onPrimaryContainer, size: 20),
          ),
          title: Text(h.title,
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(h.category,
              style: text.bodySmall?.copyWith(color: colors.outline)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => h.page()),
          ),
        );
      },
    );
  }
}

class _CenterHint extends StatelessWidget {
  const _CenterHint({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colors.outline),
            const SizedBox(height: AppSpacing.m),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.outline),
            ),
          ],
        ),
      ),
    );
  }
}
