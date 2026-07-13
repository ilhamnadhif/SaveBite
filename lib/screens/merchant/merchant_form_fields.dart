import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sb.dart';

/// Field form yang dipakai khusus oleh layar merchant.
class MerchantFormField extends StatelessWidget {
  const MerchantFormField({
    super.key,
    required this.controller,
    this.validator,
    this.hintText,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.prefixText,
    this.trailing,
    this.readOnly = false,
    this.enabled = true,
    this.onTap,
    this.onChanged,
    this.borderColor = AppColors.inputBorder,
  });

  final TextEditingController controller;
  final String? Function(String?)? validator;
  final String? hintText;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefixText;
  final Widget? trailing;
  final bool readOnly;
  final bool enabled;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              validator: validator,
              maxLines: maxLines,
              keyboardType: keyboardType,
              textInputAction: maxLines > 1
                  ? TextInputAction.newline
                  : textInputAction,
              textCapitalization: textCapitalization,
              inputFormatters: inputFormatters,
              readOnly: readOnly,
              enabled: enabled,
              onTap: onTap,
              onChanged: onChanged,
              style: AppText.ui(14.5, color: AppColors.ink),
              cursorColor: AppColors.greenBright,
              decoration: InputDecoration(
                isDense: true,
                hintText: hintText,
                hintStyle: AppText.ui(14.5, color: AppColors.mutedAlt),
                prefixText: prefixText,
                prefixStyle: AppText.ui(14.5, color: AppColors.body),
                border: InputBorder.none,
                errorMaxLines: 2,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (trailing != null)
            Padding(padding: const EdgeInsets.only(top: 10), child: trailing!),
        ],
      ),
    );
  }
}

/// Menjaga input harga tetap berupa digit dengan pemisah ribuan Indonesia.
class RupiahInputFormatter extends TextInputFormatter {
  const RupiahInputFormatter({this.maxDigits = 9});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > maxDigits) {
      digits = digits.substring(0, maxDigits);
    }
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (digits.isEmpty) return TextEditingValue.empty;

    final grouped = formatMerchantPriceInput(digits);
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
  }
}

String formatMerchantPriceInput(Object value) {
  final digits = value.toString().replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  final result = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) result.write('.');
    result.write(digits[i]);
  }
  return result.toString();
}

int? parseMerchantPrice(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

int? parseMerchantTimeMinutes(String raw) {
  final match = RegExp(r'^(\d{2})[.:](\d{2})$').firstMatch(raw.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

TimeOfDay merchantTimeFromText(String raw, {required TimeOfDay fallback}) {
  final minutes = parseMerchantTimeMinutes(raw);
  if (minutes == null) return fallback;
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

String formatMerchantTime(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}.'
    '${time.minute.toString().padLeft(2, '0')}';

DateTime merchantDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime merchantDateTime(DateTime date, String time) {
  final minutes = parseMerchantTimeMinutes(time)!;
  return DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);
}

String formatMerchantDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${date.day.toString().padLeft(2, '0')} '
      '${months[date.month - 1]} ${date.year}';
}
