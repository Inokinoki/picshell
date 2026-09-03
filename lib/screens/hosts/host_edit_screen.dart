import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../models/forward_rule.dart';
import '../../models/host.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';

const _uuid = Uuid();

class HostEditScreen extends ConsumerStatefulWidget {
  final String? hostId;

  const HostEditScreen({super.key, this.hostId});

  @override
  ConsumerState<HostEditScreen> createState() => _HostEditScreenState();
}

class _HostEditScreenState extends ConsumerState<HostEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  AuthType _authType = AuthType.password;
  String? _selectedKeyId;
  String? _proxyHostId;
  List<ForwardRule> _forwards = [];
  bool _isEditing = false;

  Host? _loadedHost;

  @override
  void initState() {
    super.initState();
    if (widget.hostId != null) {
      _isEditing = true;
      final hosts = ref.read(hostListProvider);
      // Deep links can carry stale ids; don't crash on an unknown host.
      _loadedHost = hosts.where((h) => h.id == widget.hostId).firstOrNull;
    }
    final host = _loadedHost;
    if (host != null) {
      _nameController.text = host.name;
      _hostController.text = host.hostname;
      _portController.text = host.port.toString();
      _userController.text = host.username;
      _authType = host.authType;
      _passwordController.text = host.password ?? '';
      _selectedKeyId = host.keyId;
      _proxyHostId = host.proxyHostId;
      _forwards = List.of(host.forwards);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(keyListProvider);
    final hosts = ref.watch(hostListProvider);
    // Jump-via-jump is not supported: hide hosts that route through another
    // jump host so they can't be picked as a proxy here.
    final jumpChoices = hosts
        .where((h) => h.id != widget.hostId && h.proxyHostId == null)
        .toList();
    // Likewise, this host cannot gain a jump host of its own while other
    // hosts already route through it — that would create a jump chain.
    final isUsedAsJumpHost = _isUsedAsJumpHost(hosts);
    // If the saved selection is no longer offered (the chosen jump host now
    // routes via another jump itself, or this host became someone's jump),
    // render null instead of an orphaned value — DropdownButton asserts that
    // its value matches exactly one item.
    final selectionOrphaned = _proxyHostId != null &&
        (isUsedAsJumpHost ||
            jumpChoices.every((h) => h.id != _proxyHostId));
    final effectiveProxyHostId = selectionOrphaned ? null : _proxyHostId;
    final jumpHost = effectiveProxyHostId == null
        ? null
        : hosts.where((h) => h.id == effectiveProxyHostId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing
            ? (_loadedHost != null ? 'Edit Host' : 'Host Not Found')
            : 'Add Host'),
        actions: [IconButton(icon: const Icon(Icons.save), onPressed: _save)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RadioGroup<AuthType>(
          groupValue: _authType,
          onChanged: (v) {
            if (v != null) {
              setState(() => _authType = v);
            }
          },
          child: Form(
            key: _formKey,
            child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              TextFormField(
                controller: _hostController,
                decoration:
                    const InputDecoration(labelText: 'Hostname / IP'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final port = int.tryParse(v ?? '');
                  if (port == null || port < 1 || port > 65535) {
                    return 'Port must be 1–65535';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _sectionLabel(context, 'Authentication'),
              ListTile(
                title: const Text('Password'),
                leading: const Radio<AuthType>(
                  value: AuthType.password,
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_authType == AuthType.password)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                ),
              ListTile(
                title: const Text('SSH Key'),
                leading: const Radio<AuthType>(
                  value: AuthType.key,
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_authType == AuthType.key)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: keys.isEmpty
                            ? const Text(
                                'No keys imported yet',
                                style: TextStyle(color: Colors.grey),
                              )
                            : DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Select Key',
                                  border: OutlineInputBorder(),
                                ),
                                initialValue: _selectedKeyId,
                                items: keys
                                    .map(
                                      (k) => DropdownMenuItem(
                                        value: k.id,
                                        child: Text(k.name),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (id) =>
                                    setState(() => _selectedKeyId = id),
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.vpn_key),
                        tooltip: 'Manage SSH Keys',
                        onPressed: () => context.push('/keys'),
                      ),
                    ],
                  ),
                ),
              ListTile(
                title: const Text('SSH Agent'),
                subtitle: const Text(
                  'Uses keys from ~/.ssh/ directory',
                  style: TextStyle(fontSize: 12),
                ),
                leading: const Radio<AuthType>(
                  value: AuthType.agent,
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 16),
              _sectionLabel(context, 'Jump Host'),
              DropdownButtonFormField<String?>(
                decoration: const InputDecoration(
                  labelText: 'Connect via (ProxyJump, ssh -J)',
                  border: OutlineInputBorder(),
                ),
                value: effectiveProxyHostId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Direct connection'),
                    ),
                    ...jumpChoices.map(
                      (h) => DropdownMenuItem<String?>(
                        value: h.id,
                        child: Text('${h.name} (${h.username}@${h.hostname}:${h.port})'),
                      ),
                    ),
                  ],
                  onChanged: (id) => setState(() => _proxyHostId = id),
                ),
                // Hosts routed via another jump host are hidden above; note
                // it so the list shrinking isn't mysterious.
                if (hosts.any((h) =>
                    h.id != widget.hostId && h.proxyHostId != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Hosts that themselves route via a jump host cannot be '
                      'used as a jump host.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (selectionOrphaned)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'The previously selected jump host is no longer '
                      'available (it now routes via another jump host, or '
                      'this host is itself used as a jump host); the '
                      'connection falls back to direct unless you pick a '
                      'different jump host.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              if (jumpHost != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tip: save the jump host first, then select it here. '
                    'Its credentials are read from the saved entry.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              _sectionLabel(context, 'Port Forwarding'),
              if (_forwards.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No port forwards configured',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final rule in _forwards)
                  ListTile(
                    leading: Icon(_forwardIcon(rule.type)),
                    title: Text(rule.summary,
                        style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text(rule.autoStart ? 'Auto-start' : 'Manual'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: 'Edit',
                          onPressed: () => _editForward(rule),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Remove',
                          onPressed: () => _removeForward(rule),
                        ),
                      ],
                    ),
                  ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addForward,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Forward'),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _save, child: const Text('Save')),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  IconData _forwardIcon(ForwardType type) {
    switch (type) {
      case ForwardType.local:
        return Icons.south_east;
      case ForwardType.remote:
        return Icons.north_west;
      case ForwardType.socks:
        return Icons.shuffle;
    }
  }

  Future<void> _addForward() async {
    final rule = await _showForwardEditor();
    if (rule != null) setState(() => _forwards = [..._forwards, rule]);
  }

  Future<void> _editForward(ForwardRule existing) async {
    final rule = await _showForwardEditor(existing: existing);
    if (rule != null) {
      setState(() {
        _forwards = [
          for (final f in _forwards) if (f.id != existing.id) f else rule,
        ];
      });
    }
  }

  Future<void> _removeForward(ForwardRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove forward?'),
        content: Text(rule.summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _forwards = _forwards.where((f) => f.id != rule.id).toList());
    }
  }

  /// Editor for a single [ForwardRule]. Returns null if the user cancels.
  /// All three types (local, remote, SOCKS) are offered; SOCKS needs only a
  /// local port.
  Future<ForwardRule?> _showForwardEditor({ForwardRule? existing}) {
    return showDialog<ForwardRule>(
      context: context,
      builder: (ctx) => _ForwardEditorDialog(existing: existing),
    );
  }

  /// Whether another saved host routes through the host being edited (i.e.
  /// this host is someone's jump host). Such a host must not gain a jump host
  /// of its own — picshell does not support jump chains.
  bool _isUsedAsJumpHost(List<Host> hosts) => widget.hostId != null &&
      hosts.any((h) => h.proxyHostId == widget.hostId);

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_authType == AuthType.key && _selectedKeyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an SSH key')),
      );
      return;
    }

    final notifier = ref.read(hostListProvider.notifier);
    final password =
        _authType == AuthType.password ? _passwordController.text : null;
    final keyId = _authType == AuthType.key ? _selectedKeyId : null;
    final port = int.parse(_portController.text);
    final forwards = List<ForwardRule>.of(_forwards);
    // Never persist an orphaned or chain-forming jump selection (see build).
    final hosts = ref.read(hostListProvider);
    final offeredIds = hosts
        .where((h) => h.id != widget.hostId && h.proxyHostId == null)
        .map((h) => h.id)
        .toSet();
    final proxyHostId = (_isUsedAsJumpHost(hosts) ||
            !offeredIds.contains(_proxyHostId))
        ? null
        : _proxyHostId;

    if (_isEditing) {
      final host = _loadedHost;
      if (host == null) {
        Navigator.pop(context);
        return;
      }
      host.name = _nameController.text;
      host.hostname = _hostController.text;
      host.port = port;
      host.username = _userController.text;
      host.authType = _authType;
      host.password = password;
      host.keyId = keyId;
      host.proxyHostId = proxyHostId;
      host.forwards = forwards;
      notifier.update(host);
    } else {
      final host = Host(
        id: _uuid.v4(),
        name: _nameController.text,
        hostname: _hostController.text,
        port: port,
        username: _userController.text,
        authType: _authType,
        password: password,
        keyId: keyId,
        proxyHostId: proxyHostId,
        forwards: forwards,
      );
      notifier.add(host);
    }

    Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

/// Dialog for creating or editing a [ForwardRule]. Local and remote types
/// share the same fields (localPort + remoteHost:remotePort); SOCKS only needs
/// a local port (it is a dynamic proxy, the destination is chosen per request).
class _ForwardEditorDialog extends StatefulWidget {
  final ForwardRule? existing;
  const _ForwardEditorDialog({this.existing});

  @override
  State<_ForwardEditorDialog> createState() => _ForwardEditorDialogState();
}

class _ForwardEditorDialogState extends State<_ForwardEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _localPortController = TextEditingController();
  final _bindHostController = TextEditingController(text: '127.0.0.1');
  final _remoteHostController = TextEditingController();
  final _remotePortController = TextEditingController();
  ForwardType _type = ForwardType.local;
  bool _autoStart = true;

  /// Local and remote forwards need a remote target; SOCKS does not (the
  /// destination is chosen by the SOCKS client at connect time).
  bool get _needsRemote =>
      _type == ForwardType.local || _type == ForwardType.remote;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _localPortController.text = e.localPort.toString();
      _bindHostController.text = e.localHost;
      _remoteHostController.text = e.remoteHost ?? '';
      _remotePortController.text = e.remotePort?.toString() ?? '';
      _autoStart = e.autoStart;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Forward' : 'Edit Forward'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ForwardType>(
              decoration: const InputDecoration(labelText: 'Type'),
              value: _type,
              items: const [
                DropdownMenuItem(
                  value: ForwardType.local,
                  child: Text('Local  (ssh -L)'),
                ),
                DropdownMenuItem(
                  value: ForwardType.remote,
                  child: Text('Remote (ssh -R)'),
                ),
                DropdownMenuItem(
                  value: ForwardType.socks,
                  child: Text('SOCKS  (ssh -D)'),
                ),
              ],
              onChanged: (v) => setState(() => _type = v ?? ForwardType.local),
            ),
            TextFormField(
              controller: _localPortController,
              decoration: InputDecoration(
                labelText: _type == ForwardType.remote
                    ? 'Remote bind port'
                    : 'Local port',
              ),
              keyboardType: TextInputType.number,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            if (_needsRemote) ...[
              if (_type == ForwardType.remote)
                TextFormField(
                  controller: _bindHostController,
                  decoration: const InputDecoration(
                    labelText: 'Remote bind address (on server)',
                    helperText:
                        "Address the SSH server listens on. '127.0.0.1' "
                        "(default, like OpenSSH without GatewayPorts) or "
                        "'0.0.0.0' to expose on all server interfaces.",
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
              TextFormField(
                controller: _remoteHostController,
                decoration: InputDecoration(
                  labelText: _type == ForwardType.remote
                      ? 'Dial-back host (local side)'
                      : 'Remote host',
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _remotePortController,
                decoration: InputDecoration(
                  labelText: _type == ForwardType.remote
                      ? 'Dial-back port (local side)'
                      : 'Remote port',
                ),
                keyboardType: TextInputType.number,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
            ],
            SwitchListTile(
              title: const Text('Auto-start when connected'),
              value: _autoStart,
              onChanged: (v) => setState(() => _autoStart = v),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.existing == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final localPort = int.tryParse(_localPortController.text);
    if (localPort == null) return;
    // SOCKS has no fixed remote endpoint; local/remote forwards need one.
    final remotePort =
        _needsRemote ? int.tryParse(_remotePortController.text) : null;
    if (_needsRemote && remotePort == null) return;
    final rule = ForwardRule(
      id: widget.existing?.id ?? _uuid.v4(),
      type: _type,
      localHost: _type == ForwardType.remote
          ? _bindHostController.text.trim()
          : '127.0.0.1',
      localPort: localPort,
      remoteHost: _needsRemote ? _remoteHostController.text : null,
      remotePort: remotePort,
      autoStart: _autoStart,
    );
    Navigator.pop(context, rule);
  }

  @override
  void dispose() {
    _localPortController.dispose();
    _bindHostController.dispose();
    _remoteHostController.dispose();
    _remotePortController.dispose();
    super.dispose();
  }
}
