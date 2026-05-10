// lib/features/browser/browser_screen.dart
// Full UI for BRW-01: directory listing.
//
// States:
//   - Loading  → skeleton / spinner
//   - Error    → error message + retry button
//   - Empty    → "此目录为空" message
//   - Data     → scrollable list of directory + audio-file tiles

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/webdav_client.dart';
import '../../shared/models/nas_file.dart';
import 'browser_provider.dart';
import 'widgets/file_list_item.dart';

class BrowserScreen extends ConsumerWidget {
  const BrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navStack = ref.watch(navigationStackProvider);
    final currentPath = navStack.last;

    final contentsAsync = ref.watch(directoryContentsProvider(currentPath));

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件浏览器'),
        centerTitle: true,
        leading: navStack.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回上级',
                onPressed: () {
                  ref.read(navigationStackProvider.notifier).pop();
                },
              )
            : null,
      ),
      body: Column(
        children: [
          // Current path indicator
          _PathBar(path: currentPath),
          const Divider(height: 1),

          // Directory contents
          Expanded(
            child: contentsAsync.when(
              loading: () => const _LoadingView(),
              error: (error, _) => _ErrorView(
                message: error is WebDavException
                    ? error.message
                    : '加载失败：$error',
                onRetry: () {
                  ref.invalidate(directoryContentsProvider(currentPath));
                },
              ),
              data: (files) {
                if (files.isEmpty) {
                  return const _EmptyView();
                }
                return _FileList(files: files);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Path bar ────────────────────────────────────────────────────────────────────

class _PathBar extends StatelessWidget {
  final String path;

  const _PathBar({required this.path});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        path,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Loading state ───────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              // Icon placeholder
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 16),
              // Text placeholder
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Error state ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            '此目录为空',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ── File list ───────────────────────────────────────────────────────────────────

class _FileList extends StatelessWidget {
  final List<NasFile> files;

  const _FileList({required this.files});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: files.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final file = files[index];
        if (file.isDirectory) {
          return DirectoryListTile(
            file: file,
            onTap: (_) {
              // Directory navigation (BRW-02) — placeholder for now
            },
          );
        }
        return AudioFileListTile(
          file: file,
          onTap: (_) {
            // File playback (BRW-04) — placeholder for now
          },
        );
      },
    );
  }
}
