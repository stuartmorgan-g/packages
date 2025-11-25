// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:objective_c/objective_c.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'ffi_bindings.g.dart' as ffi_bindings;
import 'messages.g.dart';
import 'native_video_player.dart';

/// The non-test implementation of `nativePlayerProvider`.
NativeVideoPlayer _productionNativePlayerProvider(int rawPointer) {
  return _FfiNativeVideoPlayer(
    ffi_bindings.FVPVideoPlayer.fromPointer(
      ffi.Pointer<ObjCObjectImpl>.fromAddress(rawPointer),
      retain: true,
      release: true,
    ),
  );
}

/// An iOS implementation of [VideoPlayerPlatform] that uses the
/// Pigeon-generated [VideoPlayerApi].
class AVFoundationVideoPlayer extends VideoPlayerPlatform {
  /// Creates a new AVFoundation-based video player implementation instance.
  AVFoundationVideoPlayer({
    @visibleForTesting AVFoundationVideoPlayerApi? pluginApi,
    @visibleForTesting
    NativeVideoPlayer Function(int playerId)? nativePlayerProvider,
  }) : _api = pluginApi ?? AVFoundationVideoPlayerApi(),
       _nativePlayerProvider =
           nativePlayerProvider ?? _productionNativePlayerProvider;

  final AVFoundationVideoPlayerApi _api;
  // A method to create NativeVideoPlayer instances, which can be
  // overridden for testing.
  final NativeVideoPlayer Function(int rawPointer) _nativePlayerProvider;

  final Map<int, _PlayerInstance> _players = <int, _PlayerInstance>{};

  /// Registers this class as the default instance of [VideoPlayerPlatform].
  static void registerWith() {
    VideoPlayerPlatform.instance = AVFoundationVideoPlayer();
  }

  @override
  Future<void> init() {
    return _api.initialize();
  }

  @override
  Future<void> dispose(int playerId) async {
    final _PlayerInstance? player = _players.remove(playerId);
    await player?.dispose();
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    return createWithOptions(
      VideoCreationOptions(
        dataSource: dataSource,
        // Texture view was the only supported view type before
        // createWithOptions was introduced.
        viewType: VideoViewType.textureView,
      ),
    );
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final DataSource dataSource = options.dataSource;
    final VideoViewType viewType = options.viewType;

    String? uri;
    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        final String? asset = dataSource.asset;
        if (asset == null) {
          throw ArgumentError(
            '"asset" must be non-null for an asset data source',
          );
        }
        uri = await _api.getAssetUrl(asset, dataSource.package);
        if (uri == null) {
          // Throw a platform exception for compatibility with the previous
          // implementation, which threw on the native side.
          throw PlatformException(
            code: 'video_player',
            message: 'Asset $asset not found in package ${dataSource.package}.',
          );
        }
      case DataSourceType.network:
      case DataSourceType.file:
      case DataSourceType.contentUri:
        uri = dataSource.uri;
    }
    if (uri == null) {
      throw ArgumentError('Unable to construct a video asset from $options');
    }
    final pigeonCreationOptions = CreationOptions(
      uri: uri,
      httpHeaders: dataSource.httpHeaders,
    );

    final int playerId;
    final int rawPointer;
    final VideoPlayerViewState state;
    switch (viewType) {
      case VideoViewType.textureView:
        final TexturePlayerCreationResponse playerInfo = await _api
            .createForTextureView(pigeonCreationOptions);
        playerId = playerInfo.playerId;
        rawPointer = playerInfo.rawPointer;
        state = VideoPlayerTextureViewState(textureId: playerInfo.textureId);
      case VideoViewType.platformView:
        final PlatformViewPlayerCreationResponse playerInfo = await _api
            .createForPlatformView(pigeonCreationOptions);
        playerId = playerInfo.playerId;
        rawPointer = playerInfo.rawPointer;
        state = const VideoPlayerPlatformViewState();
    }
    ensurePlayerInitialized(playerId, rawPointer, state);

    return playerId;
  }

  /// Returns the API instance for [playerId], creating it if it doesn't already
  /// exist.
  @visibleForTesting
  void ensurePlayerInitialized(
    int playerId,
    int rawPointer,
    VideoPlayerViewState viewState,
  ) {
    _players.putIfAbsent(playerId, () {
      return _PlayerInstance(
        _nativePlayerProvider(rawPointer),
        viewState,
        eventChannel: EventChannel(
          // This must match the channel name used in FVPVideoPlayerPlugin.m.
          'flutter.dev/videoPlayer/videoEvents$playerId',
        ),
      );
    });
  }

  @override
  Future<void> setLooping(int playerId, bool looping) {
    return _playerWith(id: playerId).setLooping(looping);
  }

  @override
  Future<void> play(int playerId) {
    return _playerWith(id: playerId).play();
  }

  @override
  Future<void> pause(int playerId) {
    return _playerWith(id: playerId).pause();
  }

  @override
  Future<void> setVolume(int playerId, double volume) {
    return _playerWith(id: playerId).setVolume(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) {
    assert(speed > 0);

    return _playerWith(id: playerId).setPlaybackSpeed(speed);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) {
    return _playerWith(id: playerId).seekTo(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    return _playerWith(id: playerId).getPosition();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return _playerWith(id: playerId).videoEvents;
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) {
    return _api.setMixWithOthers(mixWithOthers);
  }

  @override
  Widget buildView(int playerId) {
    return buildViewWithOptions(VideoViewOptions(playerId: playerId));
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) {
    final int playerId = options.playerId;
    final VideoPlayerViewState viewState = _playerWith(id: playerId).viewState;

    return switch (viewState) {
      VideoPlayerTextureViewState(:final int textureId) => Texture(
        textureId: textureId,
      ),
      VideoPlayerPlatformViewState() => _buildPlatformView(playerId),
    };
  }

  Widget _buildPlatformView(int playerId) {
    final creationParams = PlatformVideoViewCreationParams(playerId: playerId);

    return IgnorePointer(
      // IgnorePointer so that GestureDetector can be used above the platform view.
      child: UiKitView(
        viewType: 'plugins.flutter.dev/video_player_ios',
        creationParams: creationParams,
        creationParamsCodec: AVFoundationVideoPlayerApi.pigeonChannelCodec,
      ),
    );
  }

  _PlayerInstance _playerWith({required int id}) {
    final _PlayerInstance? player = _players[id];
    return player ?? (throw StateError('No active player with ID $id.'));
  }
}

/// An instance of a video player, corresponding to a single player ID in
/// [AVFoundationVideoPlayer].
class _PlayerInstance {
  _PlayerInstance(
    this._nativePlayer,
    this.viewState, {
    required EventChannel eventChannel,
  }) : _eventChannel = eventChannel;

  final NativeVideoPlayer _nativePlayer;
  final VideoPlayerViewState viewState;
  final EventChannel _eventChannel;
  final StreamController<VideoEvent> _eventStreamController =
      StreamController<VideoEvent>.broadcast();
  StreamSubscription<dynamic>? _eventSubscription;

  Future<void> play() async => _nativePlayer.play();

  Future<void> pause() async => _nativePlayer.pause();

  Future<void> setLooping(bool looping) async =>
      _nativePlayer.setLooping(looping);

  Future<void> setVolume(double volume) async =>
      _nativePlayer.setVolume(volume);

  Future<void> setPlaybackSpeed(double speed) async =>
      _nativePlayer.setPlaybackSpeed(speed);

  Future<void> seekTo(Duration position) {
    return _nativePlayer.seekTo(position.inMilliseconds);
  }

  Future<Duration> getPosition() async {
    return Duration(milliseconds: _nativePlayer.getPosition());
  }

  Stream<VideoEvent> get videoEvents {
    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _onStreamEvent,
      onError: (Object e) {
        _eventStreamController.addError(e);
      },
    );

    return _eventStreamController.stream;
  }

  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    unawaited(_eventStreamController.close());
    _nativePlayer.dispose();
  }

  void _onStreamEvent(dynamic event) {
    final map = event as Map<dynamic, dynamic>;
    // The strings here must all match the strings in FVPEventBridge.m.
    _eventStreamController.add(switch (map['event']) {
      'initialized' => VideoEvent(
        eventType: VideoEventType.initialized,
        duration: Duration(milliseconds: map['duration'] as int),
        size: Size(
          (map['width'] as num?)?.toDouble() ?? 0.0,
          (map['height'] as num?)?.toDouble() ?? 0.0,
        ),
      ),
      'completed' => VideoEvent(eventType: VideoEventType.completed),
      'bufferingUpdate' => VideoEvent(
        buffered: (map['values'] as List<dynamic>)
            .map<DurationRange>(_toDurationRange)
            .toList(),
        eventType: VideoEventType.bufferingUpdate,
      ),
      'bufferingStart' => VideoEvent(eventType: VideoEventType.bufferingStart),
      'bufferingEnd' => VideoEvent(eventType: VideoEventType.bufferingEnd),
      'isPlayingStateUpdate' => VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: map['isPlaying'] as bool,
      ),
      _ => VideoEvent(eventType: VideoEventType.unknown),
    });
  }

  DurationRange _toDurationRange(dynamic value) {
    final pair = value as List<dynamic>;
    final startMilliseconds = pair[0] as int;
    final durationMilliseconds = pair[1] as int;
    return DurationRange(
      Duration(milliseconds: startMilliseconds),
      Duration(milliseconds: startMilliseconds + durationMilliseconds),
    );
  }
}

/// Base class representing the state of a video player view.
@visibleForTesting
@immutable
sealed class VideoPlayerViewState {
  const VideoPlayerViewState();
}

/// Represents the state of a video player view that uses a texture.
@visibleForTesting
final class VideoPlayerTextureViewState extends VideoPlayerViewState {
  /// Creates a new instance of [VideoPlayerTextureViewState].
  const VideoPlayerTextureViewState({required this.textureId});

  /// The ID of the texture used by the video player.
  final int textureId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoPlayerTextureViewState && other.textureId == textureId;

  @override
  int get hashCode => textureId.hashCode;
}

/// Represents the state of a video player view that uses a platform view.
@visibleForTesting
final class VideoPlayerPlatformViewState extends VideoPlayerViewState {
  /// Creates a new instance of [VideoPlayerPlatformViewState].
  const VideoPlayerPlatformViewState();
}

class _FfiNativeVideoPlayer implements NativeVideoPlayer {
  final ffi_bindings.FVPVideoPlayer _fvpVideoPlayer;

  _FfiNativeVideoPlayer(this._fvpVideoPlayer);

  @override
  void play() => _fvpVideoPlayer.play();

  @override
  void pause() => _fvpVideoPlayer.pause();

  @override
  int getPosition() => _fvpVideoPlayer.position;

  @override
  void setVolume(double volume) => _fvpVideoPlayer.setVolume(volume);

  @override
  void setPlaybackSpeed(double speed) =>
      _fvpVideoPlayer.setPlaybackSpeed(speed);

  @override
  Future<void> seekTo(int positionMilliseconds) async {
    final Completer<void> seekFinished = Completer<void>();
    _fvpVideoPlayer.seekTo(
      positionMilliseconds,
      completion: ffi_bindings.ObjCBlock_ffiVoid.fromFunction(() {
        seekFinished.complete();
      }),
    );
    return seekFinished.future;
  }

  @override
  void setLooping(bool looping) => _fvpVideoPlayer.setLooping(looping);

  @override
  void dispose() => _fvpVideoPlayer.dispose();
}
