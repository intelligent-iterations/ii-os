import '../models/image_edit_selection.dart';
import '../models/models.dart';
import 'api_client.dart';

final class ImageEditSubmissionService {
  const ImageEditSubmissionService(this.api);

  final ApiClient api;

  Future<ImageEditSubmission> submit({
    required String workspaceId,
    required WorkflowTemplateModel template,
    required JsonMap input,
    bool ghostMode = false,
    bool keptEnhancedText = false,
  }) async {
    try {
      final response = await api.post(
        'v1/workspaces/$workspaceId/jobs',
        body: {
          'workflowKey': template.id,
          if (ghostMode) 'ghostMode': true,
          if (keptEnhancedText) 'promptEnhancementBypass': 'user_enhanced',
          'input': input,
        },
      );
      return ImageEditSubmission.success(
        template: template,
        response: asJsonMap(response['data']),
      );
    } on Object catch (error) {
      return ImageEditSubmission.failure(template: template, failure: error);
    }
  }
}
