/// Identifiers for records created on this device before the server assigns
/// its own.
///
/// IDs keep the `PREFIX-<microseconds since epoch>` shape, so they still sort
/// by creation time, but are strictly increasing: records created within the
/// same microsecond (for example the children of a group assignment, or
/// back-to-back outbox mutations) never share an ID.
int _lastLocalIdMicros = 0;

String newLocalId(String prefix, [DateTime? at]) {
  var micros = (at ?? DateTime.now()).toUtc().microsecondsSinceEpoch;
  if (micros <= _lastLocalIdMicros) micros = _lastLocalIdMicros + 1;
  _lastLocalIdMicros = micros;
  return '$prefix-$micros';
}
