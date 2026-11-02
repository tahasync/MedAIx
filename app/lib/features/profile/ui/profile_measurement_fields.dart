/// Shared controls used by profile, sign-up and onboarding screens.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/widgets.dart';
import '../../../theme/app_theme.dart';
import '../providers/profile_form.dart';

/// Metric / imperial toggle for 3.2.
class UnitToggle extends StatelessWidget {
  const UnitToggle({
    super.key,
    required this.unit,
    required this.onChanged,
    this.enabled = true,
  });

  final UnitSystem unit;
  final ValueChanged<UnitSystem> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.chipGap,
      runSpacing: AppSpace.chipGap,
      children: [
        AppChip(
          label: 'cm / kg',
          selected: unit == UnitSystem.metric,
          onTap: enabled ? () => onChanged(UnitSystem.metric) : null,
        ),
        AppChip(
          label: 'ft / lb',
          selected: unit == UnitSystem.imperial,
          onTap: enabled ? () => onChanged(UnitSystem.imperial) : null,
        ),
      ],
    );
  }
}

/// 3.2 — height and weight. Values in and out are always cm / kg; the
/// fields convert on the unit toggle and round sensibly (whole cm, one
/// decimal kg, whole inches and pounds).
class HeightWeightFields extends StatefulWidget {
  const HeightWeightFields({
    super.key,
    required this.heightCm,
    required this.weightKg,
    required this.unit,
    required this.onHeightChanged,
    required this.onWeightChanged,
    this.heightError,
    this.weightError,
    this.enabled = true,
    this.heightKey,
    this.weightKey,
  });

  final double? heightCm;
  final double? weightKg;
  final UnitSystem unit;

  /// Null when cleared; NaN when the text is not a number.
  final ValueChanged<double?> onHeightChanged;
  final ValueChanged<double?> onWeightChanged;
  final String? heightError;
  final String? weightError;
  final bool enabled;
  final Key? heightKey;
  final Key? weightKey;

  @override
  State<HeightWeightFields> createState() => _HeightWeightFieldsState();
}

class _HeightWeightFieldsState extends State<HeightWeightFields> {
  final TextEditingController _height = TextEditingController();
  final TextEditingController _feet = TextEditingController();
  final TextEditingController _inches = TextEditingController();
  final TextEditingController _weight = TextEditingController();

  @override
  void initState() {
    super.initState();
    _writeFromValues();
  }

  @override
  void didUpdateWidget(HeightWeightFields old) {
    super.didUpdateWidget(old);
    if (widget.unit != old.unit) _writeFromValues();
  }

  @override
  void dispose() {
    _height.dispose();
    _feet.dispose();
    _inches.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// Fills the fields from the canonical cm / kg values for the current
  /// unit; only called when the unit flips, so typing is never overwritten.
  void _writeFromValues() {
    final double? h = widget.heightCm;
    final double? w = widget.weightKg;
    final bool hOk = h != null && !h.isNaN;
    final bool wOk = w != null && !w.isNaN;
    if (widget.unit == UnitSystem.metric) {
      _height.text = hOk ? ProfileValidation.formatNumber(h) : '';
      _weight.text = wOk ? ProfileValidation.formatNumber(w) : '';
    } else {
      if (hOk) {
        final (:int feet, :int inches) = Units.cmToFeetInches(h);
        _feet.text = feet.toString();
        _inches.text = inches.toString();
      } else {
        _feet.text = '';
        _inches.text = '';
      }
      _weight.text = wOk ? Units.kgToLb(w).toString() : '';
    }
  }

  void _heightMetricChanged(String raw) =>
      widget.onHeightChanged(parseNumber(raw));

  void _heightImperialChanged() {
    final String ft = _feet.text.trim();
    final String inch = _inches.text.trim();
    if (ft.isEmpty && inch.isEmpty) {
      widget.onHeightChanged(null);
      return;
    }
    final int? feet = ft.isEmpty ? 0 : int.tryParse(ft);
    final int? inches = inch.isEmpty ? 0 : int.tryParse(inch);
    if (feet == null || inches == null) {
      widget.onHeightChanged(double.nan);
      return;
    }
    widget.onHeightChanged(Units.feetInchesToCm(feet, inches));
  }

  void _weightChanged(String raw) {
    final double? value = parseNumber(raw);
    if (value == null || value.isNaN || widget.unit == UnitSystem.metric) {
      widget.onWeightChanged(value);
      return;
    }
    widget.onWeightChanged(Units.lbToKg(value));
  }

  @override
  Widget build(BuildContext context) {
    const TextInputType decimal = TextInputType.numberWithOptions(
      decimal: true,
    );
    final bool metric = widget.unit == UnitSystem.metric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metric)
          TextField(
            key: widget.heightKey,
            controller: _height,
            enabled: widget.enabled,
            keyboardType: decimal,
            textInputAction: TextInputAction.next,
            onChanged: _heightMetricChanged,
            decoration: InputDecoration(
              labelText: 'Height',
              suffixText: 'cm',
              errorText: widget.heightError,
              errorMaxLines: 3,
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: widget.heightKey,
                  controller: _feet,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _heightImperialChanged(),
                  decoration: InputDecoration(
                    labelText: 'Height',
                    suffixText: 'ft',
                    errorText: widget.heightError,
                    errorMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: TextField(
                  controller: _inches,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _heightImperialChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Inches',
                    suffixText: 'in',
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: AppSpace.lg),
        TextField(
          key: widget.weightKey,
          controller: _weight,
          enabled: widget.enabled,
          keyboardType: decimal,
          textInputAction: TextInputAction.done,
          onChanged: _weightChanged,
          decoration: InputDecoration(
            labelText: 'Weight',
            suffixText: metric ? 'kg' : 'lb',
            errorText: widget.weightError,
            errorMaxLines: 3,
          ),
        ),
      ],
    );
  }
}
