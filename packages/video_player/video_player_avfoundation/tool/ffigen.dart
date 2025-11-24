// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:ffigen/ffigen.dart';

void main() {
  final Uri packageRoot = Platform.script.resolve('../');
  FfiGenerator(
    output: Output(
      dartFile: packageRoot.resolve('lib/src/ffi_bindings.g.dart'),
      objectiveCFile: packageRoot.resolve(
        'darwin/video_player_avfoundation/Sources/video_player_avfoundation/FFIBindings.g.m',
      ),
      /*style: const DynamicLibraryBindings(
        wrapperName: 'FoundationFFI',
        wrapperDocComment: 'Bindings for NSFileManager.',
      ),*/
    ),
    headers: Headers(
      entryPoints: <Uri>[
        packageRoot.resolve(
          'darwin/video_player_avfoundation/Sources/video_player_avfoundation/include/video_player_avfoundation/FVPVideoPlayer.h',
        ),
      ],
    ),
    objectiveC: ObjectiveC(
      interfaces: Interfaces(
        include: (Declaration declaration) {
          return <String>{'FVPVideoPlayer'}.contains(declaration.originalName);
        },
      ),
      categories: const Categories(includeTransitive: false),
    ),
  ).generate();
}
