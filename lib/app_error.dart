import 'package:firebase_auth/firebase_auth.dart';

class AppException implements Exception {
  final String userMessage;
  final String? code;
  final String? originalMessage;

  AppException(
    this.userMessage, {
    this.code,
    this.originalMessage,
  });

  @override
  String toString() {
    final buffer = StringBuffer('AppException: $userMessage');
    if (code != null && code!.isNotEmpty) buffer.write(' (code=$code)');
    if (originalMessage != null && originalMessage!.isNotEmpty) {
      buffer.write(' (message=$originalMessage)');
    }
    return buffer.toString();
  }
}

String authErrorMessage(String code) {
  switch (code) {
    case 'invalid-email':
      return 'Please enter a valid email address.';
    case 'user-disabled':
      return 'This account has been disabled. Contact support.';
    case 'user-not-found':
      return 'No account found for that email.';
    case 'wrong-password':
      return 'Incorrect password. Please try again.';
    case 'invalid-credential':
      return 'Invalid credentials. Please try again.';
    case 'too-many-requests':
      return 'Too many attempts. Please wait and try again.';
    case 'operation-not-allowed':
      return 'Email/password sign-in is not enabled.';
    case 'network-request-failed':
      return 'Network error. Check your internet connection.';
    case 'weak-password':
      return 'Your password is too weak.';
    case 'requires-recent-login':
      return 'Please log in again and retry.';
    case 'app-not-authorized':
      return 'This app is not authorized to use Firebase Auth.';
    case 'internal-error':
      return 'An internal error occurred. Please try again.';
    case 'invalid-verification-code':
      return 'The verification code is invalid.';
    case 'invalid-verification-id':
      return 'The verification session is invalid.';
    case 'credential-already-in-use':
      return 'This credential is already associated with another user.';
    case 'email-already-in-use':
      return 'That email is already in use.';
    case 'expired-action-code':
      return 'This action link has expired.';
    case 'invalid-action-code':
      return 'This action link is invalid.';
    case 'missing-email':
      return 'Please enter your email.';
    case 'missing-password':
      return 'Please enter your password.';
    case 'user-token-expired':
      return 'Your session expired. Please sign in again.';
    case 'account-exists-with-different-credential':
      return 'An account already exists with a different sign-in method.';
    case 'provider-already-linked':
      return 'This provider is already linked to your account.';
    case 'invalid-continue-uri':
      return 'The continue URL is invalid.';
    case 'unauthorized-continue-uri':
      return 'The continue URL is not authorized.';
    case 'quota-exceeded':
      return 'Service quota exceeded. Please try again later.';
    default:
      return 'Authentication failed. Please try again.';
  }
}

String firestoreErrorMessage(String code) {
  switch (code) {
    case 'permission-denied':
      return 'You do not have permission to perform this action.';
    case 'unauthenticated':
      return 'You are not signed in. Please log in and try again.';
    case 'not-found':
      return 'The requested item was not found.';
    case 'already-exists':
      return 'This item already exists.';
    case 'unavailable':
      return 'Service is temporarily unavailable. Please try again.';
    case 'deadline-exceeded':
      return 'The request timed out. Please try again.';
    case 'resource-exhausted':
      return 'Service quota exceeded. Please try again later.';
    case 'failed-precondition':
      return 'The operation could not be completed in the current state.';
    case 'aborted':
      return 'The operation was aborted. Please try again.';
    case 'cancelled':
      return 'The operation was cancelled.';
    case 'invalid-argument':
      return 'An invalid value was provided.';
    case 'out-of-range':
      return 'A value was out of range.';
    case 'data-loss':
      return 'Data loss occurred. Please try again.';
    case 'internal':
      return 'An internal error occurred. Please try again.';
    case 'unknown':
      return 'An unknown error occurred. Please try again.';
    default:
      return 'Request failed. Please try again.';
  }
}

AppException mapAuthException(FirebaseAuthException e) {
  return AppException(
    authErrorMessage(e.code),
    code: e.code,
    originalMessage: e.message,
  );
}

AppException mapFirestoreException(FirebaseException e) {
  return AppException(
    firestoreErrorMessage(e.code),
    code: e.code,
    originalMessage: e.message,
  );
}

bool isMissingIndexError(Object? error) {
  return error is FirebaseException && error.code == 'failed-precondition';
}

String missingIndexUserMessage(FirebaseException e) {
  final details = e.message ?? 'A Firestore index is missing for this query.';
  return 'Missing Firestore index.\n\n$details';
}
