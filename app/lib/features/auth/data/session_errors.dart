/// Helpers for identifying an expired API session across feature screens.
library;

import '../../../data/api/api_client.dart';
import '../../reports/data/reports_repository.dart';

bool isSessionExpired(Object? error) {
  if (error is ApiException) return error.statusCode == 401;
  if (error is RepositoryException) {
    final Object? cause = error.cause;
    return cause is ApiException && cause.statusCode == 401;
  }
  return false;
}
