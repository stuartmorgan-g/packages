// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/messages.g.dart',
  kotlinOut:
      'android/src/main/kotlin/io/flutter/plugins/googlesignin/Messages.kt',
  kotlinOptions: KotlinOptions(package: 'io.flutter.plugins.googlesignin'),
  copyrightHeader: 'pigeons/copyright.txt',
))

/// Pigeon version of SignInOption.
// TODO(stuartmorgan): Remove this, and deprecate it in the API; it doesn't
// seem to be a thing any more.
enum SignInType {
  /// Default configuration.
  standard,

  /// Recommended configuration for game sign in.
  games,
}

/// Pigeon version of SignInInitParams.
///
/// See SignInInitParams for details.
class InitParams {
  /// The parameters to use when initializing the sign in process.
  const InitParams({
    this.scopes = const <String>[],
    this.signInType = SignInType.standard,
    this.hostedDomain,
    this.clientId,
    this.serverClientId,
    this.forceCodeForRefreshToken = false,
    this.forceAccountName,
  });

  final List<String> scopes;
  final SignInType signInType;
  // TODO(stuartmorgan): Deprecate and remove? Seems not to exist any more.
  final String? hostedDomain;
  final String? clientId;
  final String? serverClientId;
  final bool forceCodeForRefreshToken;
  final String? forceAccountName;
}

/// Pigeon version of GoogleSignInUserData.
///
/// See GoogleSignInUserData for details.
class UserData {
  UserData({
    required this.email,
    required this.id,
    this.displayName,
    this.photoUrl,
    this.idToken,
    this.serverAuthCode,
  });

  final String? displayName;
  final String email;
  final String id;
  final String? photoUrl;
  final String? idToken;
  final String? serverAuthCode;
}

@HostApi()
abstract class GoogleSignInApi {
  /// Initializes a sign in request with the given parameters.
  void init(InitParams params);

  /// Starts a silent sign in.
  @async
  UserData signInSilently();

  /// Starts a sign in with user interaction.
  @async
  UserData signIn();

  /// Requests the access token for the current sign in.
  @async
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  String getAccessToken(String email, bool shouldRecoverAuth);

  /// Signs out the current user.
  @async
  void signOut();

  /// Revokes scope grants to the application.
  @async
  void disconnect();

  /// Returns whether the user is currently signed in.
  bool isSignedIn();

  /// Clears the authentication caching for the given token, requiring a
  /// new sign in.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void clearAuthCache(String token);

  /// Requests access to the given scopes.
  @async
  bool requestScopes(List<String> scopes);
}

/// The information necessary to build a an authorization request.
///
/// Corresponds to the native AuthorizationRequest object, but only contains
/// the fields used by this plugin.
class PlatformAuthorizationRequest {
  PlatformAuthorizationRequest({required this.scopes});
  List<String> scopes;
}

/// The information necessary to build a credential request.
///
/// Combines the parts of the native GetCredentialRequest and CredentialOption
/// classes that are used for this plugin.
class GetCredentialRequestParams {
  GetCredentialRequestParams({
    required this.filterToAuthorized,
    required this.autoSelectEnabled,
    this.serverClientId,
  });
  bool filterToAuthorized;
  bool autoSelectEnabled;
  String? serverClientId;
}

/// Pigeon equivalent of the native GoogleIdTokenCredential.
class PlatformGoogleIdTokenCredential {
  String? displayName;
  String? familyName;
  String? givenName;
  late String id;
  late String idToken;
  String? profilePictureUri;
}

enum GetCredentialFailureType {
  /// Indicates that a credential was returned, but it was not of the expected
  /// type.
  unexpectedCredentialType,

  /// Indicates that a server client ID was not provided.
  missingServerClientId,

  // Types from https://developer.android.com/reference/android/credentials/GetCredentialException
  /// The request was internally interrupted.
  interrupted,

  /// The request was canceled by the user.
  canceled,

  /// No matching credential was found.
  noCredential,

  /// The provider was not properly configured.
  providerConfigurationIssue,

  /// The credential manager is not supported on this device.
  unsupported,

  /// The request failed for an unknown reason.
  unknown,
}

/// The response from a `getCredential` call.
///
/// This is not the same as a native GetCredentialResponse since modeling the
/// response type hierarchy and two-part callback in this interface layer would
/// add a lot of complexity that is not needed for the plugin's use case. It is
/// instead a processed version of the results of those callbacks.
sealed class GetCredentialResult {}

/// An authentication failure.
class GetCredentialFailure extends GetCredentialResult {
  /// The type of failure.
  late GetCredentialFailureType type;

  /// The message associated with the failure, if any.
  String? message;
}

/// A successful authentication result.
class GetCredentialSuccess extends GetCredentialResult {
  late PlatformGoogleIdTokenCredential credential;
}

enum AuthorizeFailureType {
  /// Indicates that the requested types are not currently authorized.
  ///
  /// This is returned only if promptIfUnauthorized is false, indicating that
  /// the user would need to be prompted for authorization.
  unauthorized,

  /// Indicates that the call to AuthorizationClient.authorize itself failed.
  authorizeFailure,

  /// Corresponds to SendIntentException, indicating that the pending intent is
  /// no longer available.
  pendingIntentException,

  /// Corresponds to an SendIntentException in onActivityResult, indicating that
  /// either authorization failed, or the result was not available for some
  /// reason.
  apiException,

  /// Indicates that the user needs to be prompted for authorization, but there
  /// is no current activity to prompt in.
  noActivity,
}

/// The response from an `authorize` call.
sealed class AuthorizeResult {}

/// An authorization failure
class AuthorizeFailure extends AuthorizeResult {
  /// The type of failure.
  late AuthorizeFailureType type;

  /// The message associated with the failure, if any.
  String? message;
}

/// A successful authorization result.
///
/// Corresponds to a native AuthorizationResult.
class PlatformAuthorizationResult extends AuthorizeResult {
  String? accessToken;
  String? serverAuthCode;
  late List<String> grantedScopes;
}

@HostApi()
abstract class CredentialManagerApi {
  @async
  GetCredentialResult getCredential(GetCredentialRequestParams params);

  @async
  void clearCredentialState();
}

@HostApi()
abstract class AuthorizationClientApi {
  @async
  AuthorizeResult authorize(PlatformAuthorizationRequest params,
      {required bool promptIfUnauthorized});
}
