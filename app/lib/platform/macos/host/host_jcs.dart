import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Canonical JSON serialization for the JSON subset used in Host operation
/// hashes. Object keys are sorted by UTF-16 code units and array order stays
/// unchanged, as specified by RFC 8785.
String canonicalizeHostJson(Object? value) {
  final active = <Object>{};
  return _canonicalize(value, active, 0);
}

/// Hashes method and named params. Call with HostRpcRequest.operationPayload,
/// which excludes the request ID and operation ID by construction.
String hashHostOperationPayload(Object? payload) =>
    sha256.convert(utf8.encode(canonicalizeHostJson(payload))).toString();

String _canonicalize(Object? value, Set<Object> active, int depth) {
  if (depth > 64) throw const FormatException('JSON nesting is too deep');
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is String) return _quoteJcsString(value);
  if (value is int) return _jcsNumber(value.toDouble());
  if (value is double) return _jcsNumber(value);
  if (value is List) {
    if (!active.add(value)) throw const FormatException('Cyclic JSON array');
    try {
      return '[${value.map((item) => _canonicalize(item, active, depth + 1)).join(',')}]';
    } finally {
      active.remove(value);
    }
  }
  if (value is Map) {
    if (!active.add(value)) throw const FormatException('Cyclic JSON object');
    try {
      if (value.keys.any((key) => key is! String)) {
        throw const FormatException('JSON object keys must be strings');
      }
      final keys = value.keys.cast<String>().toList()..sort(_compareUtf16);
      return '{${keys.map((key) => '${_quoteJcsString(key)}:${_canonicalize(value[key], active, depth + 1)}').join(',')}}';
    } finally {
      active.remove(value);
    }
  }
  throw FormatException('Unsupported JSON value: ${value.runtimeType}');
}

String _quoteJcsString(String value) {
  final result = StringBuffer('"');
  for (var index = 0; index < value.length; index++) {
    final code = value.codeUnitAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      if (index + 1 >= value.length) {
        throw const FormatException('Invalid Unicode surrogate');
      }
      final low = value.codeUnitAt(index + 1);
      if (low < 0xdc00 || low > 0xdfff) {
        throw const FormatException('Invalid Unicode surrogate');
      }
      result
        ..writeCharCode(code)
        ..writeCharCode(low);
      index++;
      continue;
    }
    if (code >= 0xdc00 && code <= 0xdfff) {
      throw const FormatException('Invalid Unicode surrogate');
    }
    switch (code) {
      case 0x08:
        result.write(r'\b');
      case 0x09:
        result.write(r'\t');
      case 0x0a:
        result.write(r'\n');
      case 0x0c:
        result.write(r'\f');
      case 0x0d:
        result.write(r'\r');
      case 0x22:
        result.write(r'\"');
      case 0x5c:
        result.write(r'\\');
      default:
        if (code < 0x20) {
          result.write('\\u${code.toRadixString(16).padLeft(4, '0')}');
        } else {
          result.writeCharCode(code);
        }
    }
  }
  return '${result.toString()}"';
}

String _jcsNumber(double value) {
  if (!value.isFinite) throw const FormatException('Non-finite JSON number');
  if (value == 0) return '0';

  final negative = value.isNegative;
  final source = value.abs().toString().toLowerCase();
  final exponentIndex = source.indexOf('e');
  final mantissa = exponentIndex < 0
      ? source
      : source.substring(0, exponentIndex);
  final exponent = exponentIndex < 0
      ? 0
      : int.parse(source.substring(exponentIndex + 1));
  final dotIndex = mantissa.indexOf('.');
  var decimalPosition = (dotIndex < 0 ? mantissa.length : dotIndex) + exponent;
  var digits = mantissa.replaceAll('.', '');
  while (digits.length > 1 && digits.startsWith('0')) {
    digits = digits.substring(1);
    decimalPosition--;
  }
  while (digits.length > 1 && digits.endsWith('0')) {
    digits = digits.substring(0, digits.length - 1);
  }

  final sign = negative ? '-' : '';
  if (decimalPosition > 0 && decimalPosition <= 21) {
    if (digits.length <= decimalPosition) {
      return '$sign$digits${'0' * (decimalPosition - digits.length)}';
    }
    return '$sign${digits.substring(0, decimalPosition)}.${digits.substring(decimalPosition)}';
  }
  if (decimalPosition <= 0 && decimalPosition > -6) {
    return '$sign'
        '0.${'0' * -decimalPosition}$digits';
  }
  final scientificExponent = decimalPosition - 1;
  final fraction = digits.length > 1 ? '.${digits.substring(1)}' : '';
  final exponentSign = scientificExponent >= 0 ? '+' : '';
  return '$sign${digits[0]}$fraction'
      'e$exponentSign$scientificExponent';
}

int _compareUtf16(String left, String right) {
  final leftCodes = left.codeUnits;
  final rightCodes = right.codeUnits;
  final commonLength = leftCodes.length < rightCodes.length
      ? leftCodes.length
      : rightCodes.length;
  for (var index = 0; index < commonLength; index++) {
    final comparison = leftCodes[index].compareTo(rightCodes[index]);
    if (comparison != 0) return comparison;
  }
  return leftCodes.length.compareTo(rightCodes.length);
}
