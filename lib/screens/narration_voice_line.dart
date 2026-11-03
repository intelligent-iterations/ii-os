part of 'narration_generation_form.dart';

/// Which voice reads the script.
class _SpokenBy extends StatelessWidget {
  const _SpokenBy({required this.voiceModel});

  final String voiceModel;

  @override
  Widget build(BuildContext context) {
    final palette = IiOsPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.mic2, size: IiOsIconSize.md, color: palette.brand.text),
        IiOsGap.hXs,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_voiceLabels[voiceModel] ?? voiceModel, style: text.titleSmall),
              Text(
                'A clear, neutral reading voice. Add a sample below to have it '
                'match a different one.',
                style: text.bodySmall?.copyWith(color: palette.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The voices the narration workflow accepts, by the value it is sent.
const _voiceLabels = <String, String>{'chatterbox-turbo': 'Chatterbox Turbo'};
