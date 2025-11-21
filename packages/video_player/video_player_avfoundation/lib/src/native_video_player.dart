// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Abstract interface for a native video player.
///
/// Workaround for https://github.com/dart-lang/native/issues/2778.
abstract class NativeVideoPlayer {
  Future<void> play();
  Future<void> pause();
  Future<int> getPosition();
  Future<void> setVolume(double volume);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> seekTo(int positionMilliseconds);
  Future<void> setLooping(bool looping);
  Future<void> dispose();
}
