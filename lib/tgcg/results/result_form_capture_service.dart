import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/models.dart';
import '../evidence/device_evidence_service.dart';

class CapturedResultForm {
  const CapturedResultForm({
    required this.evidence,
    required this.rawText,
    required this.partyVotes,
    required this.extractionConfidence,
    this.totalVotes,
    this.accreditedVoters,
    this.rejectedVotes,
    this.registeredVoters,
  });

  final CapturedEvidence evidence;
  final String rawText;
  final Map<String, int> partyVotes;
  final double extractionConfidence;
  final int? totalVotes;
  final int? accreditedVoters;
  final int? rejectedVotes;
  final int? registeredVoters;

  bool get hasOcr => rawText.trim().isNotEmpty;
}

class ResultFormCaptureService {
  ResultFormCaptureService({
    DeviceEvidenceService? evidenceService,
  }) : _evidenceService = evidenceService ?? DeviceEvidenceService();

  final DeviceEvidenceService _evidenceService;
  TextRecognizer? _recognizer;

  Future<CapturedResultForm?> capture() async {
    final photo = await _evidenceService.capturePhoto();
    if (photo == null) return null;

    double? latitude;
    double? longitude;
    try {
      final location = await _evidenceService.captureLocation();
      latitude = location.latitude;
      longitude = location.longitude;
    } catch (_) {
      // GPS absence is preserved as an integrity finding rather than
      // fabricating a location or discarding the captured form.
    }

    final evidence = CapturedEvidence(
      type: EvidenceType.resultForm,
      fileName: photo.fileName,
      mimeType: photo.mimeType,
      createdAt: photo.createdAt,
      path: photo.path,
      contentHash: photo.contentHash,
      latitude: latitude,
      longitude: longitude,
    );

    final path = photo.path;
    if (path == null ||
        path.isEmpty ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return CapturedResultForm(
        evidence: evidence,
        rawText: '',
        partyVotes: const {},
        extractionConfidence: 0,
      );
    }

    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final recognized = await _recognizer!.processImage(
      InputImage.fromFilePath(path),
    );
    return ResultFormParser.parse(
      evidence: evidence,
      rawText: recognized.text,
    );
  }

  Future<void> dispose() async {
    final recognizer = _recognizer;
    if (recognizer != null) {
      await recognizer.close();
    }
    await _evidenceService.dispose();
  }
}

class ResultFormParser {
  const ResultFormParser._();

  static CapturedResultForm parse({
    required CapturedEvidence evidence,
    required String rawText,
  }) {
    final partyVotes = <String, int>{};
    for (final party in const ['P1', 'P2', 'P3', 'P4']) {
      final spacedParty = party.replaceFirst('P', 'P ');
      final value = _extract(
        rawText,
        [
          RegExp(
            '\\b$party\\b[^0-9]{0,24}([0-9][0-9,]*)',
            caseSensitive: false,
          ),
          RegExp(
            '\\b$spacedParty\\b[^0-9]{0,24}([0-9][0-9,]*)',
            caseSensitive: false,
          ),
        ],
      );
      if (value != null) partyVotes[party] = value;
    }

    final total = _extract(
      rawText,
      [
        RegExp(
          '\\b(?:TOTAL|VALID\\s+VOTES?)\\b[^0-9]{0,24}([0-9][0-9,]*)',
          caseSensitive: false,
        ),
      ],
    );
    final accredited = _extract(
      rawText,
      [
        RegExp(
          '\\bACCREDITED(?:\\s+VOTERS?)?\\b[^0-9]{0,24}([0-9][0-9,]*)',
          caseSensitive: false,
        ),
      ],
    );
    final rejected = _extract(
      rawText,
      [
        RegExp(
          '\\bREJECTED(?:\\s+VOTES?)?\\b[^0-9]{0,24}([0-9][0-9,]*)',
          caseSensitive: false,
        ),
      ],
    );
    final registered = _extract(
      rawText,
      [
        RegExp(
          '\\bREGISTERED(?:\\s+VOTERS?)?\\b[^0-9]{0,24}([0-9][0-9,]*)',
          caseSensitive: false,
        ),
      ],
    );

    const expectedFields = 8;
    final extractedFields = partyVotes.length +
        [total, accredited, rejected, registered]
            .where((value) => value != null)
            .length;
    final confidence =
        (extractedFields / expectedFields).clamp(0.0, 1.0).toDouble();

    return CapturedResultForm(
      evidence: evidence,
      rawText: rawText,
      partyVotes: Map.unmodifiable(partyVotes),
      extractionConfidence: confidence,
      totalVotes: total,
      accreditedVoters: accredited,
      rejectedVotes: rejected,
      registeredVoters: registered,
    );
  }

  static int? _extract(String text, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final raw = match.group(1)?.replaceAll(',', '');
      final value = int.tryParse(raw ?? '');
      if (value != null) return value;
    }
    return null;
  }
}
