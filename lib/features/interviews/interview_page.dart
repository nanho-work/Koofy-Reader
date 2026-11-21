import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

const _endpoint = String.fromEnvironment(
  'READER_STORY_URL',
  defaultValue:
      'https://asia-northeast3-koofy-reader.cloudfunctions.net/readerStory',
);

String label(BuildContext context, String ko, String en, String ja) =>
    switch (Localizations.localeOf(context).languageCode) {
      'ko' => ko,
      'ja' => ja,
      _ => en,
    };

String interviewsTitle(BuildContext context) =>
    label(context, '사람을 만나다', 'Interviews', 'インタビュー');

Uri _url(String action, {String? id, String? photo}) =>
    Uri.parse(_endpoint).replace(
      queryParameters: {
        'action': action,
        if (id != null) 'id': id,
        if (photo != null) 'photo': photo,
      },
    );

Future<Map<String, dynamic>> _read(String? id) async {
  const timeout = Duration(seconds: 15);
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client
        .getUrl(_url(id == null ? 'interviews' : 'interview', id: id))
        .timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Interview API returned ${response.statusCode}');
    }
    return jsonDecode(
          await response.transform(utf8.decoder).join().timeout(timeout),
        )
        as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

class InterviewPage extends StatefulWidget {
  const InterviewPage({super.key, this.id});

  final String? id;

  @override
  State<InterviewPage> createState() => _InterviewPageState();
}

class _InterviewPageState extends State<InterviewPage> {
  late Future<Map<String, dynamic>> _data = _read(widget.id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(interviewsTitle(context))),
      body: SafeArea(
        top: false,
        child: FutureBuilder(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label(
                          context,
                          '인터뷰를 불러오지 못했어요.',
                          'Could not load interviews.',
                          'インタビューを読み込めませんでした。',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _data = _read(widget.id)),
                        child: Text(
                          label(context, '다시 시도', 'Try again', '再試行'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            final data = snapshot.requireData;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: widget.id == null
                    ? _list(context, data)
                    : _article(context, data),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _list(BuildContext context, Map<String, dynamic> data) {
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    if (items.isEmpty) {
      return Center(
        child: Text(
          label(
            context,
            '아직 공개된 인터뷰가 없어요.',
            'No interviews have been published yet.',
            '公開中のインタビューはまだありません。',
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final item = items[index];
        final id = item['id'] as String;
        final description = _field(item, 'summary');
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => InterviewPage(id: id)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_field(item, 'cover').isNotEmpty)
                  AspectRatio(
                    aspectRatio: 3 / 2,
                    child: _photo(
                      context,
                      id,
                      _field(item, 'cover'),
                      _field(item, 'coverAlt'),
                      fit: BoxFit.cover,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _field(item, 'title'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (_field(item, 'person').isNotEmpty)
                        Text(_field(item, 'person')),
                      if (description.isNotEmpty ||
                          _field(item, 'subtitle').isNotEmpty)
                        Text(
                          description.isEmpty
                              ? _field(item, 'subtitle')
                              : description,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _article(BuildContext context, Map<String, dynamic> article) {
    final theme = Theme.of(context).textTheme;
    final id = widget.id!;
    final blocks = (article['blocks'] as List).cast<Map<String, dynamic>>();
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text(_field(article, 'title'), style: theme.headlineMedium),
          if (_field(article, 'subtitle').isNotEmpty)
            Text(_field(article, 'subtitle'), style: theme.titleMedium),
          if (_field(article, 'person').isNotEmpty)
            Text(_field(article, 'person')),
          if (_field(article, 'cover').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: _photo(
                context,
                id,
                _field(article, 'cover'),
                _field(article, 'coverAlt'),
              ),
            ),
          for (final block in blocks)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: switch (block['type']) {
                'qa' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _field(block, 'question'),
                      style: theme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _paragraph(context, _field(block, 'answer')),
                  ],
                ),
                'photo' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _photo(
                      context,
                      id,
                      _field(block, 'photo'),
                      _field(block, 'alt'),
                    ),
                    if (_field(block, 'caption').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _field(block, 'caption'),
                          style: theme.bodySmall,
                        ),
                      ),
                  ],
                ),
                _ => _paragraph(context, _field(block, 'text')),
              },
            ),
        ],
      ),
    );
  }

  Widget _paragraph(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7),
  );

  String _field(Map<String, dynamic> value, String key) =>
      value[key] as String? ?? '';

  Widget _photo(
    BuildContext context,
    String id,
    String hash,
    String alt, {
    BoxFit fit = BoxFit.contain,
  }) {
    return Image.network(
      _url('interviewPhoto', id: id, photo: hash).toString(),
      width: double.infinity,
      fit: fit,
      semanticLabel: alt.isEmpty ? null : alt,
      excludeFromSemantics: alt.isEmpty,
      errorBuilder: (_, _, _) => Center(
        child: Text(
          label(
            context,
            '사진을 불러오지 못했어요.',
            'Image unavailable.',
            '画像を読み込めませんでした。',
          ),
        ),
      ),
    );
  }
}
