import 'dart:io'; // HttpDate.parse for RSS dates

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart';

import 'theme.dart'; // design tokens

// ===========================================================================
// Live News — pulls recent articles mentioning Mandaluyong from Google News.
// Free, no API key. Each headline opens the full article in the browser.
// ===========================================================================

/// A single news headline from the feed.
class NewsArticle {
  final String title;
  final String url;
  final String source;
  final DateTime? published;

  const NewsArticle({
    required this.title,
    required this.url,
    required this.source,
    this.published,
  });
}

class NewsService {
  NewsService._();

  // Google News RSS search, scoped to Mandaluyong and the Philippines edition.
  static const String _feedUrl =
      'https://news.google.com/rss/search?q=%22Mandaluyong+City%22'
      '&hl=en-PH&gl=PH&ceid=PH:en';

  /// Fetches and parses the latest Mandaluyong news headlines.
  static Future<List<NewsArticle>> fetchNews() async {
    final res = await http
        .get(Uri.parse(_feedUrl))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw 'Could not load news (error ${res.statusCode}).';
    }

    final doc = XmlDocument.parse(res.body);
    final articles = <NewsArticle>[];

    for (final item in doc.findAllElements('item')) {
      final rawTitle = item.getElement('title')?.innerText.trim() ?? '';
      final link = item.getElement('link')?.innerText.trim() ?? '';
      final source = item.getElement('source')?.innerText.trim() ?? '';
      final pubText = item.getElement('pubDate')?.innerText.trim();

      if (rawTitle.isEmpty || link.isEmpty) continue;

      DateTime? published;
      if (pubText != null) {
        try {
          published = HttpDate.parse(pubText);
        } catch (_) {
          published = null;
        }
      }

      // Google News appends " - Source" to titles; strip it for a clean look.
      var title = rawTitle;
      if (source.isNotEmpty && title.endsWith(' - $source')) {
        title = title.substring(0, title.length - source.length - 3).trim();
      }

      articles.add(NewsArticle(
        title: title,
        url: link,
        source: source,
        published: published,
      ));
    }
    return articles;
  }
}

/// Short relative time like "2h ago", "3d ago", or a date for older items.
String _timeAgo(DateTime? when) {
  if (when == null) return '';
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${when.day}/${when.month}/${when.year}';
}

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  late Future<List<NewsArticle>> _future;

  @override
  void initState() {
    super.initState();
    _future = NewsService.fetchNews();
  }

  Future<void> _refresh() async {
    setState(() => _future = NewsService.fetchNews());
    await _future;
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the article.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('News & Announcements')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<NewsArticle>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorView(onRetry: _refresh);
            }
            final articles = snapshot.data ?? const [];
            if (articles.isEmpty) {
              return _EmptyView(onRetry: _refresh);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.l),
              itemCount: articles.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.m),
              itemBuilder: (context, i) {
                if (i == 0) return const _SourceNote();
                return _NewsCard(
                  article: articles[i - 1],
                  onTap: () => _open(articles[i - 1].url),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SourceNote extends StatelessWidget {
  const _SourceNote();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.public, size: 18, color: colors.onTertiaryContainer),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              'Live headlines about Mandaluyong from Philippine news outlets. '
              'Pull down to refresh.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onTertiaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.article, required this.onTap});
  final NewsArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final meta = [
      if (article.source.isNotEmpty) article.source,
      if (article.published != null) _timeAgo(article.published),
    ].join(' · ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.primaryContainer,
                child: Icon(Icons.article_outlined,
                    color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      style:
                          text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        style: text.bodySmall?.copyWith(color: colors.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Icon(Icons.open_in_new, size: 18, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Wrapped in a scroll view so pull-to-refresh still works.
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Icon(Icons.wifi_off_outlined, size: 56, color: colors.outline),
        const SizedBox(height: AppSpacing.m),
        Center(
          child: Text(
            'Couldn\'t load the news.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: Text(
            'Check your internet connection and try again.',
            style: TextStyle(color: colors.outline),
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        Center(
          child: FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Icon(Icons.inbox_outlined, size: 56, color: colors.outline),
        const SizedBox(height: AppSpacing.m),
        Center(
          child: Text(
            'No recent news found.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        Center(
          child: FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ),
      ],
    );
  }
}
