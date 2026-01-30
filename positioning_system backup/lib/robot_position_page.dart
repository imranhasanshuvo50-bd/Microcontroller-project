import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'robot_point.dart';
import 'trilateration_plot.dart';

class RobotPositionPage extends StatefulWidget {
  const RobotPositionPage({super.key});

  @override
  State<RobotPositionPage> createState() => _RobotPositionPageState();
}

class _RobotPositionPageState extends State<RobotPositionPage> {
  static const _maxPoints = 500;
  static final RegExp _barePairPattern = RegExp(
    r'^\s*\(?\s*[-+]?\d+(?:\.\d+)?\s*[,;\s]\s*[-+]?\d+(?:\.\d+)?\s*\)?\s*$',
  );

  double _fieldWidth = 300;
  double _fieldHeight = 300;
  double _minMoveDistance = 1.5;

  late final TextEditingController _fieldWidthController;
  late final TextEditingController _fieldHeightController;
  late final TextEditingController _minMoveDistanceController;

  bool _isActive = true;

  BluetoothConnection? _connection;
  BluetoothDevice? _device;
  StreamSubscription<Uint8List>? _inputSub;
  String _rxBuffer = '';

  final List<RobotPoint> _points = <RobotPoint>[];
  ({double d1, double d2})? _latestReceivedDistances;
  ({double d1, double d2})? _latestPlottedDistances;
  RobotPoint? _latestComputedPosition;
  RobotPoint? _latestPlottedPosition;
  double? _lastMoveDistance;
  bool? _lastMovePlotted;
  bool? _lastParseOk;
  int? _lastIntersectionCount;
  String? _lastRawLine;

  bool _isConnecting = false;

  bool get _isConnected => _connection?.isConnected ?? false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _fieldWidthController = TextEditingController(text: _formatNumber(_fieldWidth));
    _fieldHeightController = TextEditingController(text: _formatNumber(_fieldHeight));
    _minMoveDistanceController = TextEditingController(text: _formatNumber(_minMoveDistance));
  }

  @override
  void activate() {
    super.activate();
    _isActive = true;
  }

  @override
  void deactivate() {
    _isActive = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _isActive = false;
    _fieldWidthController.dispose();
    _fieldHeightController.dispose();
    _minMoveDistanceController.dispose();
    unawaited(_disconnect());
    super.dispose();
  }

  Future<void> _showMessage(String message) async {
    if (!mounted || !_isActive) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _ensureBluetoothReady() async {
    if (!_isAndroid) {
      await _showMessage('Bluetooth serial is supported on Android only.');
      return false;
    }

    final connectStatus = await Permission.bluetoothConnect.request();
    final scanStatus = await Permission.bluetoothScan.request();
    if (connectStatus.isPermanentlyDenied || scanStatus.isPermanentlyDenied) {
      await _showMessage('Bluetooth permission was denied permanently. Enable it in Settings.');
      await openAppSettings();
      return false;
    }
    if (!connectStatus.isGranted || !scanStatus.isGranted) {
      await _showMessage('Bluetooth permissions (Connect/Scan) are required to connect.');
      return false;
    }

    final enabled = await FlutterBluetoothSerial.instance.requestEnable();
    if (enabled != true) {
      await _showMessage('Please enable Bluetooth to connect.');
      return false;
    }

    return true;
  }

  Future<BluetoothDevice?> _pickBondedDevice() async {
    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    if (!mounted) return null;

    if (devices.isEmpty) {
      await _showMessage('No paired devices found. Pair the ESP32 in Android settings first.');
      return null;
    }

    return showModalBottomSheet<BluetoothDevice>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: devices.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final d = devices[index];
              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(d.name ?? 'Unknown device'),
                subtitle: Text(d.address),
                onTap: () => Navigator.of(context).pop(d),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _connect() async {
    if (_isConnected || _isConnecting) return;

    final ready = await _ensureBluetoothReady();
    if (!ready) return;

    final device = await _pickBondedDevice();
    if (device == null) return;

    setState(() {
      _isConnecting = true;
      _device = device;
    });

    try {
      final connection = await BluetoothConnection.toAddress(device.address);
      if (!mounted) {
        await connection.close();
        return;
      }

      _connection = connection;
      _inputSub = connection.input?.listen(
        _onData,
        onError: (_) => unawaited(_handleDisconnected()),
        onDone: () => unawaited(_handleDisconnected()),
        cancelOnError: true,
      );

      await _showMessage('Connected to ${device.name ?? device.address}');
    } catch (e) {
      await _showMessage('Connection failed: $e');
      _device = null;
      await _disconnect();
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _handleDisconnected() async {
    await _disconnect();
    await _showMessage('Disconnected.');
  }

  Future<void> _disconnect() async {
    await _inputSub?.cancel();
    _inputSub = null;

    await _connection?.close();
    _connection = null;

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _device = null;
      });
    }
  }

  void _clear() {
    setState(() {
      _points.clear();
      _latestReceivedDistances = null;
      _latestPlottedDistances = null;
      _latestComputedPosition = null;
      _latestPlottedPosition = null;
      _lastMoveDistance = null;
      _lastMovePlotted = null;
      _lastParseOk = null;
      _lastIntersectionCount = null;
      _lastRawLine = null;
    });
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  double? _tryParseNumber(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  Future<void> _applyPlotSettings() async {
    final width = _tryParseNumber(_fieldWidthController.text);
    final height = _tryParseNumber(_fieldHeightController.text);
    final minMove = _tryParseNumber(_minMoveDistanceController.text);

    if (width == null || height == null || minMove == null || width <= 0 || height <= 0 || minMove < 0) {
      await _showMessage('Enter valid numbers for sensor distance, plot height, and min move.');
      return;
    }

    setState(() {
      _fieldWidth = width;
      _fieldHeight = height;
      _minMoveDistance = minMove;
    });

    _fieldWidthController.text = _formatNumber(_fieldWidth);
    _fieldHeightController.text = _formatNumber(_fieldHeight);
    _minMoveDistanceController.text = _formatNumber(_minMoveDistance);
  }

  void _onData(Uint8List data) {
    final chunk = utf8.decode(data, allowMalformed: true);
    _rxBuffer += chunk;

    final lines = _rxBuffer.split(RegExp(r'[\r\n]+'));
    _rxBuffer = lines.removeLast();

    for (final line in lines) {
      _handleLine(line);
    }

    if (_barePairPattern.hasMatch(_rxBuffer)) {
      final buffered = _rxBuffer;
      _rxBuffer = '';
      _handleLine(buffered);
    }
  }

  ({double x, double y})? _parseCoordinates(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.contains(',')) {
      final parts = trimmed.split(',');
      if (parts.length >= 2) {
        final x = double.tryParse(parts[0].trim());
        final y = double.tryParse(parts[1].trim());
        if (x != null && y != null) return (x: x, y: y);
      }
    }

    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.length >= 2) {
      final x = double.tryParse(tokens[0].trim());
      final y = double.tryParse(tokens[1].trim());
      if (x != null && y != null) return (x: x, y: y);
    }

    final matches = RegExp(r'[-+]?\d+(?:\.\d+)?').allMatches(trimmed).toList();
    if (matches.length >= 2) {
      final x = double.tryParse(matches[matches.length - 2].group(0)!);
      final y = double.tryParse(matches[matches.length - 1].group(0)!);
      if (x != null && y != null) return (x: x, y: y);
    }

    return null;
  }

  void _handleLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    final parsed = _parseCoordinates(trimmed);
    final receivedDistances = parsed == null ? null : (d1: parsed.x, d2: parsed.y);

    setState(() {
      _lastRawLine = trimmed;
      _lastParseOk = receivedDistances != null;
      if (receivedDistances == null) return;

      _latestReceivedDistances = receivedDistances;

      final d1 = math.max(0.0, receivedDistances.d1);
      final d2 = math.max(0.0, receivedDistances.d2);
      final anchorA = const Offset(0, 0);
      final anchorB = Offset(_fieldWidth, 0);

      final allIntersections = circleCircleIntersections(anchorA, d1, anchorB, d2);
      _lastIntersectionCount = allIntersections.length;

      final intersectionsInFront = allIntersections.where((p) => p.dy >= 0).toList();
      final intersections = intersectionsInFront.isNotEmpty ? intersectionsInFront : allIntersections;

      RobotPoint? computed;
      if (intersections.isNotEmpty) {
        final withinField = intersections
            .where((p) => p.dx >= 0 && p.dx <= _fieldWidth && p.dy >= 0 && p.dy <= _fieldHeight)
            .toList();
        final candidates = withinField.isNotEmpty ? withinField : intersections;

        final Offset selected;
        if (_latestPlottedPosition != null) {
          final last = Offset(_latestPlottedPosition!.x, _latestPlottedPosition!.y);
          selected = candidates.reduce(
            (best, p) => (p - last).distance <= (best - last).distance ? p : best,
          );
        } else {
          selected = candidates.reduce((best, p) => p.dy <= best.dy ? p : best);
        }
        computed = RobotPoint(x: selected.dx, y: selected.dy, at: DateTime.now());
      }

      _latestComputedPosition = computed;

      if (computed == null) {
        _lastMoveDistance = null;
        _lastMovePlotted = null;
        return;
      }

      if (_latestPlottedPosition == null) {
        _latestPlottedPosition = computed;
        _latestPlottedDistances = receivedDistances;
        _points.add(computed);
        _lastMoveDistance = null;
        _lastMovePlotted = true;
        return;
      }

      final dx = computed.x - _latestPlottedPosition!.x;
      final dy = computed.y - _latestPlottedPosition!.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      _lastMoveDistance = dist;
      if (dist < _minMoveDistance) {
        _lastMovePlotted = false;
        return;
      }

      _latestPlottedPosition = computed;
      _latestPlottedDistances = receivedDistances;
      _points.add(computed);
      _lastMovePlotted = true;
      if (_points.length > _maxPoints) _points.removeRange(0, _points.length - _maxPoints);
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = _isConnected;

    final d1Text =
        _latestReceivedDistances == null ? '--' : _latestReceivedDistances!.d1.toStringAsFixed(2);
    final d2Text =
        _latestReceivedDistances == null ? '--' : _latestReceivedDistances!.d2.toStringAsFixed(2);
    final computedText = _latestComputedPosition == null
        ? '--'
        : '${_latestComputedPosition!.x.toStringAsFixed(2)}, ${_latestComputedPosition!.y.toStringAsFixed(2)}';
    final plottedText = _latestPlottedPosition == null
        ? '--'
        : '${_latestPlottedPosition!.x.toStringAsFixed(2)}, ${_latestPlottedPosition!.y.toStringAsFixed(2)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Robot Position'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: _points.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: connected ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            connected ? 'Connected' : 'Not connected',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _device?.name ?? _device?.address ?? 'ESP32 (pair in settings first)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _isConnecting
                          ? null
                          : connected
                              ? _disconnect
                              : _connect,
                      icon: Icon(connected ? Icons.link_off : Icons.link),
                      label: Text(_isConnecting ? 'Connecting…' : connected ? 'Disconnect' : 'Connect'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: _ValueTile(label: 'D1', value: d1Text),
                    ),
                    Expanded(
                      child: _ValueTile(label: 'D2', value: d2Text),
                    ),
                    Expanded(
                      child: _ValueTile(label: 'Points', value: _points.length.toString()),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                title: const Text('Plot settings'),
                subtitle: Text(
                  'Sensors: ${_formatNumber(_fieldWidth)}  •  Height: ${_formatNumber(_fieldHeight)}  •  Min move: ${_formatNumber(_minMoveDistance)}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  TextField(
                    controller: _fieldWidthController,
                    decoration: const InputDecoration(
                      labelText: 'Distance between sensors A–B (units)',
                      helperText: 'This is the distance between the two red squares.',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fieldHeightController,
                    decoration: const InputDecoration(
                      labelText: 'Field/plot height (units)',
                      helperText: 'The box shows this area; the robot can still appear outside it.',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _minMoveDistanceController,
                    decoration: const InputDecoration(
                      labelText: 'Min move to update plot (units)',
                      helperText: 'D1/D2 always update; plot updates only when move ≥ min move.',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _applyPlotSettings,
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 1,
              child: TrilaterationPlot(
                fieldSize: Size(_fieldWidth, _fieldHeight),
                anchorA: const Offset(0, 0),
                anchorB: Offset(_fieldWidth, 0),
                distanceA: _latestPlottedDistances?.d1,
                distanceB: _latestPlottedDistances?.d2,
                plottedPositions: _points,
              ),
            ),
            if (_lastRawLine != null) ...[
              const SizedBox(height: 12),
              Text('Last line: $_lastRawLine', style: Theme.of(context).textTheme.bodySmall),
              Text('Computed position: $computedText', style: Theme.of(context).textTheme.bodySmall),
              Text('Plotted position: $plottedText', style: Theme.of(context).textTheme.bodySmall),
              if (_lastParseOk != null)
                Text(
                  _lastParseOk! ? 'Parsed: OK' : 'Parsed: FAILED',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (_lastIntersectionCount != null)
                Text(
                  'Intersections: $_lastIntersectionCount',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (_lastMoveDistance != null)
                Text(
                  'Last move: ${_lastMoveDistance!.toStringAsFixed(2)}  •  ${_lastMovePlotted == true ? 'plotted' : 'ignored'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ValueTile extends StatelessWidget {
  const _ValueTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
      ],
    );
  }
}
