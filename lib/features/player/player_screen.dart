// lib/features/player/player_screen.dart
// Full player screen — PLY-01 音频流式播放.
//
// Reads the current play queue from [currentPlayQueueProvider], resolves
// WebDAV credentials from the active connection, builds a just_audio
// AudioSource with Basic Auth headers, loads it, and plays the audio
// stream.
//
// Handles loading, ready, and error states.  On auth errors (401) the
// user is prompted to check their connection credentials.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/network/webdav_client.dart';
import '../../core/services/audio_source_builder.dart';
import '../browser/browser_provider.dart';
import '../connection/connection_provider.dart';
import 'player_provider.dart';

/// The full-screen audio player.
///
/// The screen is pushed via the `/player` route after the user taps an
/// audio file in the Browser (BRW-04).  It expects [currentPlayQueueProvider]
/// to be non-null.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  /// Tracks the source-load lifecycle: idle -> loading -> ready / error.
  PlayerLoadState _loadState = PlayerLoadState.idle;

  @override
  void initState() {
    super.initState();
    // Defer the async load to the next frame so that build() runs first
    // and the loading spinner appears immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAndPlay());
  }

  // ── Load & Play ──────────────────────────────────────────────────────────────

  Future<void> _loadAndPlay() async {
    final queue = ref.read(currentPlayQueueProvider);
    if (queue == null || queue.length == 0) {
      setState(() {
        _loadState = PlayerLoadState.error('没有选择播放文件');
      });
      return;
    }

    setState(() => _loadState = PlayerLoadState.loading);

    try {
      // 1. Resolve active connection
      final activeConn = await ref.read(activeConnectionProvider.future);
      if (activeConn == null) {
        setState(() {
          _loadState = PlayerLoadState.error('没有活跃的连接',
              isAuthError: true);
        });
        return;
      }

      // 2. Read password from secure storage
      final storage = ref.read(secureStorageProvider);
      final password =
          await storage.read(key: 'connection_password_${activeConn.id}');
      if (password == null || password.isEmpty) {
        setState(() {
          _loadState = PlayerLoadState.error('密码未保存',
              isAuthError: true);
        });
        return;
      }

      // 3. Build the AudioSource with Basic Auth
      final source = AudioSourceBuilder.build(
        baseUrl: activeConn.url,
        filePath: queue.current.path,
        username: activeConn.username,
        password: password,
      );

      // 4. Load into the player
      final player = ref.read(audioPlayerProvider);
      await player.setAudioSource(source);

      // 5. Seek to resume position if present
      if (queue.startPositionMs != null) {
        await player.seek(Duration(milliseconds: queue.startPositionMs!));
      }

      setState(() => _loadState = PlayerLoadState.ready);

      // 6. Start playback
      await player.play();
    } on WebDavException catch (e) {
      setState(() {
        _loadState = PlayerLoadState.error(
          e.message,
          isAuthError: e.isAuthError,
        );
      });
    } catch (e) {
      setState(() {
        _loadState = PlayerLoadState.error('加载失败: $e');
      });
    }
  }

  /// Retry loading after an error.
  Future<void> _retry() => _loadAndPlay();

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(currentPlayQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _loadState.status == PlayerLoadStatus.ready
              ? queue?.current.name ?? '播放器'
              : '播放器',
        ),
        centerTitle: true,
      ),
      body: _buildBody(queue),
    );
  }

  Widget _buildBody(playQueue) {
    switch (_loadState.status) {
      case PlayerLoadStatus.idle:
        return const Center(child: CircularProgressIndicator());
      case PlayerLoadStatus.loading:
        return _buildLoading();
      case PlayerLoadStatus.ready:
        return _buildReady(playQueue);
      case PlayerLoadStatus.error:
        return _buildError();
    }
  }

  // ── Loading ──────────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在加载音频...'),
        ],
      ),
    );
  }

  // ── Ready / Playing ──────────────────────────────────────────────────────────

  Widget _buildReady(playQueue) {
    final fileName = playQueue?.current.name ?? '未知文件';
    final index = playQueue?.currentIndex ?? 0;
    final total = playQueue?.length ?? 1;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Spacer(),
          // Large music icon
          _NowPlayingIcon(),
          const SizedBox(height: 24),
          // File name
          Text(
            fileName,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // Queue position
          Text(
            '${index + 1} / $total',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          // Play / Pause button
          _PlayPauseButton(),
          const SizedBox(height: 24),
          // Time display
          _TimeDisplay(),
          const Spacer(),
        ],
      ),
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────────

  Widget _buildError() {
    final isAuth = _loadState.isAuthError;
    final message = _loadState.errorMessage ?? '未知错误';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAuth ? Icons.lock_outline : Icons.error_outline,
              size: 80,
              color: isAuth ? Colors.orange : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (isAuth) ...[
              const SizedBox(height: 8),
              Text(
                '请检查连接配置中的用户名和密码',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                if (isAuth) ...[
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed('/connection');
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('检查连接'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Now Playing Icon ───────────────────────────────────────────────────────────

/// Animated music icon that pulses while playing.
class _NowPlayingIcon extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);

    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;
        return Icon(
          Icons.music_note,
          size: 120,
          color: isPlaying
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[400],
        );
      },
    );
  }
}

// ── Play / Pause Button ────────────────────────────────────────────────────────

/// Play / pause toggle button.
class _PlayPauseButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);

    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;

        return IconButton.filled(
          onPressed: () {
            if (isPlaying) {
              player.pause();
            } else {
              player.play();
            }
          },
          iconSize: 64,
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          style: IconButton.styleFrom(
            minimumSize: const Size(80, 80),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(40),
            ),
          ),
        );
      },
    );
  }
}

// ── Time Display ───────────────────────────────────────────────────────────────

/// Current position and total duration display.
class _TimeDisplay extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, snapshot) {
            return Text(
              formatDuration(snapshot.data ?? Duration.zero),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            );
          },
        ),
        StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, snapshot) {
            return Text(
              formatDuration(snapshot.data),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            );
          },
        ),
      ],
    );
  }
}
