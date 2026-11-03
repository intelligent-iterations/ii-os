import 'package:flutter_test/flutter_test.dart';
import 'package:ii_os/models/prompt_guide_source.dart';

void main() {
  group('officialPromptGuideSourceFor', () {
    test('uses the model authors current image prompting guide', () {
      expect(
        officialPromptGuideSourceFor(
          workflowId: 'image-create-flux2-klein',
          targetModel: 'FLUX.2 Klein 4B',
        ).toString(),
        'https://docs.bfl.ml/guides/prompting_unified_building',
      );
      expect(
        officialPromptGuideSourceFor(
          workflowId: 'image-create-qwen-2512',
          targetModel: 'Qwen Image 2512',
        ).toString(),
        'https://github.com/QwenLM/Qwen-Image/blob/main/src/examples/tools/'
        'prompt_utils_2512.py',
      );
      expect(
        officialPromptGuideSourceFor(
          workflowId: 'image-create',
          targetModel: 'Z-Image Turbo',
        ).toString(),
        'https://tongyi-mai.github.io/Z-Image-blog/',
      );
    });

    test('uses editing guidance for image-edit and inpaint workflows', () {
      expect(
        officialPromptGuideSourceFor(
          workflowId: 'image-edit-flux2-klein',
          targetModel: 'FLUX.2 Klein 4B',
          modality: 'image_edit',
        ).toString(),
        'https://docs.bfl.ml/guides/prompting_editing_overview',
      );
      expect(
        officialPromptGuideSourceFor(
          workflowId: 'image-inpaint-qwen',
          targetModel: 'Qwen Image Edit 2511',
          modality: 'inpaint',
        ).toString(),
        'https://qwen.ai/blog?id=qwen-image-edit-2511',
      );
    });

    test('does not pretend an ii-os-authored fallback is official', () {
      expect(
        officialPromptGuideSourceFor(
          workflowId: 'image-create-other',
          targetModel: 'Uncatalogued Diffusion Model',
        ),
        isNull,
      );
    });
  });
}
