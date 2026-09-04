import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/maccms_api.dart';
import '../theme/app_colors.dart';
import '../widgets/figma_loading.dart';
import '../widgets/app_page_route.dart';

/// CMS 发布的文章列表
class CmsArticlesPage extends StatefulWidget {
  const CmsArticlesPage({super.key, this.asTabRoot = false});

  /// 作为底栏「资讯」根页时不显示返回，标题为资讯
  final bool asTabRoot;

  @override
  State<CmsArticlesPage> createState() => _CmsArticlesPageState();
}

class _CmsArticlesPageState extends State<CmsArticlesPage> {
  final _api = MacCmsApi();
  final _scroll = ScrollController();
  List<CmsArticle> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      unawaited(_loadMore());
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final list = await _api.fetchArticles(page: 1, limit: 20);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _hasMore = list.length >= 10;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    try {
      final more = await _api.fetchArticles(page: next, limit: 20);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...more];
        _page = next;
        _hasMore = more.length >= 10;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _open(CmsArticle a) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => CmsArticleDetailPage(article: a),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: !widget.asTabRoot,
        foregroundColor: const Color(0xFF181818),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 8),
            Text(
              widget.asTabRoot ? '资讯' : '文章',
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: _reload,
        child: _loading && _items.isEmpty
            ? Center(child: FigmaMetaballLoader(size: 48))
            : ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  widget.asTabRoot ? 140 + bottom : 40,
                ),
                itemCount: _items.isEmpty ? 1 : _items.length + 1,
                itemBuilder: (context, i) {
                  if (_error != null && _items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Center(
                        child: TextButton(
                          onPressed: () => unawaited(_reload()),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.brand,
                          ),
                          child: Text(
                            '$_error\n点击重试',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFamily: 'AppSans'),
                          ),
                        ),
                      ),
                    );
                  }
                  if (_items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(
                        child: Text(
                          '暂无文章',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    );
                  }
                  if (i >= _items.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: _loadingMore
                            ? const CupertinoActivityIndicator()
                            : Text(
                                _hasMore ? '' : '没有更多了',
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 12,
                                  color: Color(0xFFB0B0B5),
                                ),
                              ),
                      ),
                    );
                  }
                  final a = _items[i];
                  if (i == 0 && a.coverUrl.trim().isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ArticleHeroCard(article: a, onTap: () => _open(a)),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ArticleRowCard(article: a, onTap: () => _open(a)),
                  );
                },
              ),
      ),
    );
  }
}

class _ArticleHeroCard extends StatelessWidget {
  const _ArticleHeroCard({required this.article, required this.onTap});

  final CmsArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = article.coverUrl.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFFE8E8EC),
                    child: Icon(
                      CupertinoIcons.photo,
                      color: Color(0xFFB0B0B5),
                      size: 36,
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00000000),
                        Color(0x99000000),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (article.typeName.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            article.typeName,
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Text(
                        article.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.25,
                        ),
                      ),
                      if (article.timeText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          article.timeText,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 11,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArticleRowCard extends StatelessWidget {
  const _ArticleRowCard({required this.article, required this.onTap});

  final CmsArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = article.coverUrl.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFECECEF)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: cover.isEmpty
                      ? Container(
                          width: 96,
                          height: 72,
                          color: const Color(0xFFF0F1F3),
                          child: const Icon(
                            CupertinoIcons.doc_text,
                            color: Color(0xFFB0B0B5),
                            size: 22,
                          ),
                        )
                      : Image.network(
                          cover,
                          width: 96,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 96,
                            height: 72,
                            color: const Color(0xFFF0F1F3),
                            child: const Icon(
                              CupertinoIcons.photo,
                              color: Color(0xFFB0B0B5),
                              size: 22,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF222222),
                          height: 1.3,
                        ),
                      ),
                      if (article.subTitle.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          article.subTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 12,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                      SizedBox(height: 8),
                      Row(
                        children: [
                          if (article.typeName.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.brand.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                article.typeName,
                                style: TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brand,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              [
                                if (article.author.isNotEmpty) article.author,
                                if (article.timeText.isNotEmpty)
                                  article.timeText,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 11,
                                color: Color(0xFFB0B0B5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CmsArticleDetailPage extends StatelessWidget {
  const CmsArticleDetailPage({super.key, required this.article});

  final CmsArticle article;

  @override
  Widget build(BuildContext context) {
    final cover = article.coverUrl.trim();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF181818),
        title: Text(
          article.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          if (cover.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFFF0F1F3),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
          ],
          Text(
            article.title,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF181818),
              height: 1.3,
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              if (article.typeName.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    article.typeName,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand,
                    ),
                  ),
                ),
                SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  [
                    if (article.author.isNotEmpty) article.author,
                    if (article.timeText.isNotEmpty) article.timeText,
                  ].join(' · '),
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 12,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 18),
          Container(
            height: 3,
            width: 36,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            article.content.isEmpty ? '暂无正文' : article.content,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 15,
              height: 1.7,
              color: Color(0xFF333333),
            ),
          ),
        ],
      ),
    );
  }
}
