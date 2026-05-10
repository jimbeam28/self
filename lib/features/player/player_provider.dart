// lib/features/player/player_provider.dart
// Riverpod providers for the Player feature.
//
// Provides an AudioPlayer instance and load-state management so the
// player screen (PLY-01) can load WebDAV audio streams with Basic Auth
// and react to errors gracefully.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

// ── AudioPlayer instance ───────────────────────────────────────────────────────

/// The [AudioPlayer] instance used for playback.
///
/// Created lazily on first read and disposed when the provider container
/// is destroyed (app lifecycle).  Only one player exists application-wide.
final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(() => player.dispose());
  return player;
});

// ── Player load state ──────────────────────────────────────────────────────────

/// Lifecycle of loading an audio source into the player.
enum PlayerLoadStatus {
  /// No source has been loaded yet.
  idle,

  /// The source is being loaded / buffered.
  loading,

  /// The source is loaded and the player is ready to play.
  ready,

  /// Loading failed.
  error,
}

/// Tracks the current source-loading state of the player.
///
/// Managed by the [PlayerScreen] locally (not a global StateNotifier)
/// because the load cycle is tightly coupled to the screen lifecycle
/// (rebuilding the screen for a different file starts a fresh load).
class PlayerLoadState {
  final PlayerLoadStatus status;
  final String? errorMessage;

  /// Whether the error is an authentication failure (401 / 403).
  final bool isAuthError;

  const PlayerLoadState({
    this.status = PlayerLoadStatus.idle,
    this.errorMessage,
    this.isAuthError = false,
  });

  static const idle = PlayerLoadState();

  static const loading =
      PlayerLoadState(status: PlayerLoadStatus.loading);

  static const ready = PlayerLoadState(status: PlayerLoadStatus.ready);

  factory PlayerLoadState.error(String message, {bool isAuthError = false}) {
    return PlayerLoadState(
      status: PlayerLoadStatus.error,
      errorMessage: message,
      isAuthError: isAuthError,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerLoadState &&
          status == other.status &&
          errorMessage == other.errorMessage &&
          isAuthError == other.isAuthError;

  @override
  int get hashCode => Object.hash(status, errorMessage, isAuthError);

  @override
  String toString() =>
      'PlayerLoadState(status: $status, errorMessage: $errorMessage, '
      'isAuthError: $isAuthError)';
}

// ── Time formatting helper ─────────────────────────────────────────────────────

/// Formats a [Duration] as a human-readable timestamp.
///
/// - Durations under 1 hour: `MM:SS` (e.g. `05:30`)
/// - Durations 1 hour or more: `H:MM:SS` (e.g. `1:23:45`)
/// - Null: `--:--`
String formatDuration(Duration? duration) {
  if (duration == null) return '--:--';
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$mm:$ss';
  }
  return '$mm:$ss';
}
