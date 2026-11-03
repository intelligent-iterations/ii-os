part of 'organization_resources_dialogs.dart';

class _GcpResourceDialog extends StatefulWidget {
  const _GcpResourceDialog({required this.organizationId});

  final String organizationId;

  @override
  State<_GcpResourceDialog> createState() => _GcpResourceDialogState();
}

class _GcpResourceDialogState extends State<_GcpResourceDialog> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController(text: 'gcp_primary');
  final _name = TextEditingController(text: 'Primary GCP project');
  final _serviceAccount = TextEditingController();
  final _bucket = TextEditingController();
  final _uploadServiceAccount = TextEditingController();
  final _workloadIdentityProvider = TextEditingController();
  String? _serviceAccountError;
  bool _obscureServiceAccount = true;

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _serviceAccount
      ..clear()
      ..dispose();
    _bucket.dispose();
    _uploadServiceAccount.dispose();
    _workloadIdentityProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect GCP project'),
    content: SizedBox(
      width: IiOsWidths.prose,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Paste a Google service-account JSON value or choose its local '
                'file. ii-os uses it once to discover and check this project. '
                'The key is never stored, logged, or returned.',
              ),
              IiOsGap.vSm,
              Text(
                'The service account must be able to read project metadata, '
                'bucket metadata, service accounts, workload identity '
                'providers, and the labelled Secret Manager payloads. Label '
                'each App secret ii_os_resource=github_app and '
                'ii_os_organization_id=${widget.organizationId}. Use payload '
                '{"schemaVersion":3,"organizationId":"${widget.organizationId}",'
                '"appId":"123","privateKey":"-----BEGIN PRIVATE KEY-----\u2026"}.',
              ),
              IiOsGap.vMd,
              TextFormField(
                controller: _id,
                decoration: const InputDecoration(
                  labelText: 'Resource ID',
                  hintText: 'gcp_media',
                ),
                validator: _idValidator,
              ),
              IiOsGap.vSm,
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Display name'),
                validator: _nameValidator,
              ),
              IiOsGap.vSm,
              TextFormField(
                controller: _serviceAccount,
                minLines: _obscureServiceAccount ? 1 : 8,
                maxLines: _obscureServiceAccount ? 1 : 14,
                obscureText: _obscureServiceAccount,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Service account JSON',
                  errorText: _serviceAccountError,
                  alignLabelWithHint: true,
                  suffixIcon: IconButton(
                    tooltip: _obscureServiceAccount
                        ? 'Show service account JSON'
                        : 'Hide service account JSON',
                    onPressed: () => setState(
                      () => _obscureServiceAccount = !_obscureServiceAccount,
                    ),
                    icon: Icon(
                      _obscureServiceAccount
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              IiOsGap.vSm,
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: _chooseFile,
                  child: const Text('Choose JSON file'),
                ),
              ),
              IiOsGap.vMd,
              const Text(
                'Optional: name a resource only when the project has more '
                'than one candidate.',
              ),
              IiOsGap.vSm,
              TextFormField(
                controller: _bucket,
                decoration: const InputDecoration(
                  labelText: 'Bucket name (optional)',
                ),
              ),
              IiOsGap.vSm,
              TextFormField(
                controller: _uploadServiceAccount,
                decoration: const InputDecoration(
                  labelText: 'Workflow upload service account (optional)',
                ),
              ),
              IiOsGap.vSm,
              TextFormField(
                controller: _workloadIdentityProvider,
                decoration: const InputDecoration(
                  labelText: 'Workload identity provider (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Discover and add')),
    ],
  );

  void _submit() {
    if (!_form.currentState!.validate()) return;
    try {
      final bytes = utf8.encode(_serviceAccount.text);
      final decoded = jsonDecode(_serviceAccount.text);
      if (bytes.length > 64 * 1024 ||
          decoded is! Map ||
          decoded['type'] != 'service_account') {
        throw const FormatException();
      }
      Navigator.pop(
        context,
        OrganizationGcpResourceDraft(
          id: _id.text.trim(),
          name: _name.text.trim(),
          serviceAccountJson: _serviceAccount.text,
          bucket: _bucket.text.trim(),
          uploadServiceAccount: _uploadServiceAccount.text.trim(),
          workloadIdentityProvider: _workloadIdentityProvider.text.trim(),
          permissions: const {
            'assets.read',
            'assets.write',
            'workflows.upload',
          },
        ),
      );
    } on FormatException {
      setState(() {
        _serviceAccountError =
            'Choose a valid Google service-account JSON file under 64 KiB.';
      });
    }
  }

  Future<void> _chooseFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Google service account', extensions: ['json']),
      ],
    );
    if (file == null) return;
    try {
      final length = await file.length();
      if (length > 64 * 1024) {
        if (mounted) {
          setState(() {
            _serviceAccountError =
                'Choose a Google service-account JSON file under 64 KiB.';
          });
        }
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 64 * 1024) {
        if (mounted) {
          setState(() {
            _serviceAccountError =
                'Choose a Google service-account JSON file under 64 KiB.';
          });
        }
        return;
      }
      final value = utf8.decode(bytes);
      if (mounted) {
        setState(() {
          _serviceAccount.text = value;
          _serviceAccountError = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _serviceAccountError = 'The selected JSON file could not be read.';
        });
      }
    }
  }
}
