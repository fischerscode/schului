import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import 'windows_bridge.dart';

class WebPageView extends StatefulWidget {
  const WebPageView({super.key});
  @override
  State<WebPageView> createState() => _WebPageViewState();
}

class _WebPageViewState extends State<WebPageView> {
  WebviewController? controller;
  Timer? timer;
  final subscriptions = <StreamSubscription<dynamic>>[];
  bool busy = false, visible = false, loading = true;
  String? loadedUrl, error;
  String pageTitle = 'Webseite', instructions = '';

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 300), (_) => sync());
    unawaited(sync());
  }

  Future<void> sync({bool reload = false}) async {
    if (busy) return;
    busy = true;
    try {
      final state = await bridge.invokeMapMethod<String, dynamic>('state');
      if (!mounted || state == null) return;
      final nextVisible = state['webPageVisible'] == true;
      final url = state['webPageUrl'] as String? ?? '';
      final nextTitle = state['webPageTitle'] as String? ?? 'Webseite';
      final nextInstructions = state['webPageInstructions'] as String? ?? '';
      if (pageTitle != nextTitle || instructions != nextInstructions) {
        setState(() {
          pageTitle = nextTitle;
          instructions = nextInstructions;
        });
      }
      final changed = nextVisible != visible;
      visible = nextVisible;
      if (!visible) {
        if (changed && controller != null) await controller!.suspend();
        return;
      }
      if (controller == null) {
        if (error != null && !reload) return;
        if (await WebviewController.getWebViewVersion() == null) {
          if (mounted) {
            setState(
              () => error = 'Zum Öffnen fehlt Microsoft Edge WebView2. Bitte die WebView2 Runtime installieren.',
            );
          }
          return;
        }
        final view = WebviewController();
        await view.initialize();
        if (!mounted) {
          await view.dispose();
          return;
        }
        controller = view;
        subscriptions.add(
          view.loadingState.listen((state) {
            if (mounted) {
              setState(() => loading = state == LoadingState.loading);
            }
          }),
        );
        subscriptions.add(
          view.onLoadError.listen((_) {
            if (mounted) {
              setState(() {
                error = 'Die Webseite konnte nicht geladen werden. Prüfe die Internetverbindung und versuche es erneut.';
                loading = false;
              });
            }
          }),
        );
        await view.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      } else if (changed) {
        await controller!.resume();
      }
      if (!mounted) return;
      if (loadedUrl != url || reload) {
        setState(() {
          error = null;
          loading = true;
        });
        await controller!.loadUrl(url);
        loadedUrl = url;
      }
      if (mounted) setState(() {});
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => error = 'Die Windows-Anbindung fehlt. Bitte starte SchulUI vollständig neu.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Die Webseite konnte nicht geöffnet werden. Versuche es erneut.',
        );
      }
    } finally {
      busy = false;
    }
  }

  Future<void> close() => bridge.invokeMethod<void>('webPage', null);

  @override
  void dispose() {
    timer?.cancel();
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    if (controller != null) unawaited(controller!.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebPagePanel(
    title: pageTitle,
    instructions: instructions,
    onClose: () => unawaited(close()),
    onRetry: () => unawaited(sync(reload: true)),
    loading: loading,
    error: error,
    child: controller == null ? const SizedBox.expand() : Webview(controller!),
  );
}

class WebPagePanel extends StatelessWidget {
  const WebPagePanel({
    super.key,
    required this.child,
    required this.onClose,
    required this.onRetry,
    this.loading = false,
    this.error,
    this.title = 'Webseite',
    this.instructions = '',
  });
  final Widget child;
  final VoidCallback onClose, onRetry;
  final bool loading;
  final String? error;
  final String title, instructions;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
    child: Focus(
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.language_outlined,
                      color: Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      tooltip: 'Schließen',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (instructions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .25,
                    ),
                    child: SingleChildScrollView(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(instructions),
                      ),
                    ),
                  ),
                ),
              SizedBox(
                height: 3,
                child: loading && error == null
                    ? const LinearProgressIndicator()
                    : const SizedBox(),
              ),
              Expanded(
                child: error == null
                    ? Stack(
                        children: [
                          Positioned.fill(child: child),
                          if (loading)
                            const Center(
                              child: Card(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('Webseite wird geladen …'),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off, size: 40),
                              const SizedBox(height: 16),
                              Text(error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Erneut laden'),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
