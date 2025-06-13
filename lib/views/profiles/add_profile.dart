import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/pages/scan.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:fl_clash/models/models.dart';

class AddProfileView extends StatefulWidget {
  final BuildContext context;
  final String? importUrl;

  const AddProfileView({
    super.key,
    required this.context,
    this.importUrl
  });

  @override
  State<AddProfileView> createState() => _AddProfileViewState();
}

class _AddProfileViewState extends State<AddProfileView> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _labelController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    print('AddProfileView initState, importUrl: ${widget.importUrl}');
    if (widget.importUrl != null) {
      _urlController.text = widget.importUrl!;
      print('设置 URL 控制器文本: ${widget.importUrl}');
      _importFromUrl(widget.importUrl!);
    }
  }

  Future<void> _importFromUrl(String url) async {
    print('开始从 URL 导入: $url');
    if (!mounted) {
      print('组件未挂载，取消导入');
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    print('设置加载状态为 true');

    try {
      print('开始创建 Profile');
      final profile = await Profile.normal(url: url).update();
      print('Profile 创建成功: ${profile.label ?? profile.id}');
      
      if (!mounted) {
        print('组件未挂载，取消后续操作');
        return;
      }
      
      print('开始添加 Profile');
      await globalState.appController.addProfile(profile);
      print('Profile 添加成功');
      
      Navigator.of(context).pop();
      print('关闭添加配置页面');
      
      if (mounted) {
        print('显示导入成功提示');
        context.showNotifier(appLocalizations.importSuccess);
      }
    } catch (e) {
      print('导入失败: $e');
      if (mounted) {
        context.showNotifier(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        print('设置加载状态为 false');
      }
    }
  }

  _handleAddProfileFormFile() async {
    globalState.appController.addProfileFormFile();
  }

  _handleAddProfileFormURL(String url) async {
    globalState.appController.addProfileFormURL(url);
  }

  _toScan() async {
    if (system.isDesktop) {
      globalState.appController.addProfileFormQrCode();
      return;
    }
    final url = await BaseNavigator.push(
      context,
      const ScanPage(),
    );
    if (url != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleAddProfileFormURL(url);
      });
    }
  }

  _toAdd() async {
    final url = await globalState.showCommonDialog<String>(
      child: InputDialog(
        autovalidateMode: AutovalidateMode.onUnfocus,
        title: appLocalizations.importFromURL,
        labelText: appLocalizations.url,
        value: '',
        validator: (value) {
          if (value == null || value.isEmpty) {
            return appLocalizations.emptyTip("").trim();
          }
          if (!value.isUrl) {
            return appLocalizations.urlTip("").trim();
          }
          return null;
        },
      ),
    );
    if (url != null) {
      _handleAddProfileFormURL(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    print('构建 AddProfileView');
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: appLocalizations.url,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return appLocalizations.required;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _labelController,
            decoration: InputDecoration(
              labelText: appLocalizations.label,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : () {
              if (_formKey.currentState?.validate() ?? false) {
                _importFromUrl(_urlController.text);
              }
            },
            child: _isLoading
                ? const CircularProgressIndicator()
                : Text(appLocalizations.import),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    print('AddProfileView dispose');
    _urlController.dispose();
    _labelController.dispose();
    super.dispose();
  }
}

class URLFormDialog extends StatefulWidget {
  const URLFormDialog({super.key});

  @override
  State<URLFormDialog> createState() => _URLFormDialogState();
}

class _URLFormDialogState extends State<URLFormDialog> {
  final urlController = TextEditingController();

  _handleAddProfileFormURL() async {
    final url = urlController.value.text;
    if (url.isEmpty) return;
    Navigator.of(context).pop<String>(url);
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: appLocalizations.importFromURL,
      actions: [
        TextButton(
          onPressed: _handleAddProfileFormURL,
          child: Text(appLocalizations.submit),
        )
      ],
      child: SizedBox(
        width: 300,
        child: Wrap(
          runSpacing: 16,
          children: [
            TextField(
              keyboardType: TextInputType.url,
              minLines: 1,
              maxLines: 5,
              onSubmitted: (_) {
                _handleAddProfileFormURL();
              },
              onEditingComplete: _handleAddProfileFormURL,
              controller: urlController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.url,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
