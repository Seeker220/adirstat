import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_treemap/treemap.dart';

void main() {
  runApp(const StorageScannerApp());
}

class StorageScannerApp extends StatelessWidget {
  const StorageScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "ADirStat",
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system, // Auto switch based on system settings
      home: const StorageScanner(),
    );
  }
}

class StorageScanner extends StatefulWidget {
  const StorageScanner({super.key});

  @override
  _StorageScannerState createState() => _StorageScannerState();
}

class _StorageScannerState extends State<StorageScanner> {
  final TextEditingController _pathController = TextEditingController(text: '/');
  final Map<String, List<String>> inodeDict = {};
  final Map<String, String> inodeTypeDict = {};
  final platform = const MethodChannel('com.example.adirstat/shell');

  TreeNode? rootNode;
  TreeNode? selectedNode;
  bool isScanning = false;

  Set<String> expandedPaths = {};
  int explorerRefresh = 0;
  String bytesToHuman(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes < 1024 * 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }
  final List<Color> colorPalette = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.brown,
    Colors.cyan,
    Colors.indigo,
    Colors.lime,
    Colors.pink,
    Colors.amber,
  ];
  Map<String, Color> parentFolderColorMap = {};

  String scanRoot = '/';

  final ScrollController explorerScrollController = ScrollController();
  final Map<String, GlobalKey> explorerKeys = {};

  String scanningDirRelativePath = '';

  // Fullscreen mode toggle
  bool isFullscreen = false;

  // Focus for catching keyboard events (esc/back)
  final FocusNode _focusNode = FocusNode();

  Future<String> runShellCommand(String command) async {
    try {
      final result = await platform.invokeMethod('runCommand', {'command': command});
      return result.toString();
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<void> startScan() async {
    final startPath = _pathController.text.trim();
    if (startPath.isEmpty) return;

    setState(() {
      inodeDict.clear();
      inodeTypeDict.clear();
      rootNode = null;
      isScanning = true;
      selectedNode = null;
      expandedPaths.clear();
      parentFolderColorMap.clear();
      scanRoot = startPath;
      scanningDirRelativePath = '';
    });

    rootNode = await bfsBuildTree(startPath);

    setState(() {
      isScanning = false;
      explorerRefresh++;
    });
  }

  Future<TreeNode> bfsBuildTree(String startPath) async {
    Queue<Map<String, dynamic>> bfsQueue = Queue();
    Map<String, TreeNode> nodeByPath = {};

    // Root node
    TreeNode root = TreeNode(
      name: _basename(startPath),
      size: 0,
      type: 'Directory',
      fullPath: startPath,
      children: [],
    );
    nodeByPath[startPath] = root;
    bfsQueue.add({'path': startPath, 'node': root});

    while (bfsQueue.isNotEmpty) {
      var current = bfsQueue.removeFirst();
      String currentPath = current['path'];
      TreeNode parentNode = current['node'];

      String relPath = _relativePath(currentPath, startPath);
      setState(() {
        scanningDirRelativePath = relPath;
      });

      String lsOutput = await runShellCommand('ls -lia -1 "$currentPath"');
      String duOutput = await runShellCommand('du -a -h -d 1 "$currentPath" 2>/dev/null | busybox sort -rh');
      Map<String, String> duSizes = parseDuOutput(duOutput);
      List<Map<String, dynamic>> lsEntries = parseLsOutput(lsOutput, currentPath);

      // Build children, sorted by duSizes (descending)
      List<TreeNode> children = [];
      for (var entry in lsEntries) {
        String inode = entry['inode'];
        String name = entry['name'];
        String type = entry['type'];
        String? target = entry['target'];
        String fullPath = currentPath.endsWith('/') ? '$currentPath$name' : '$currentPath/$name';

        // Store type for inode (for explorer rendering)
        inodeTypeDict[inode] = type;

        if (inodeDict.containsKey(inode)) {
          TreeNode ignoredNode = TreeNode(
            name: name,
            size: 0,
            type: 'Duplicate',
            target: inodeDict[inode]!.first,
            fullPath: fullPath,
            children: [],
            inode: inode,
          );
          children.add(ignoredNode);
          continue;
        }

        inodeDict[inode] = [fullPath];

        if (type == 'Symlink') {
          TreeNode symlinkNode = TreeNode(
            name: name,
            size: 0,
            type: 'Symlink',
            target: target,
            fullPath: fullPath,
            children: [],
            inode: inode,
          );
          children.add(symlinkNode);
          nodeByPath[fullPath] = symlinkNode;
          continue;
        }

        String sizeString = duSizes[fullPath] ?? '0';
        int sizeBytes = parseSizeToBytes(sizeString);

        if (type == 'Directory') {
          TreeNode childDirNode = TreeNode(
            name: name,
            size: sizeBytes,
            type: type,
            target: null,
            fullPath: fullPath,
            children: [],
            inode: inode,
          );
          nodeByPath[fullPath] = childDirNode;
          children.add(childDirNode);
          bfsQueue.add({'path': fullPath, 'node': childDirNode});
        } else {
          TreeNode fileNode = TreeNode(
            name: name,
            size: sizeBytes,
            type: type,
            target: null,
            fullPath: fullPath,
            children: [],
            inode: inode,
          );
          children.add(fileNode);
          nodeByPath[fullPath] = fileNode;
        }
      }

      // Sort current children by size descending (from du)
      children.sort((a, b) => b.size.compareTo(a.size));
      parentNode.children = children;

      setState(() {});
    }
    return root;
  }

  List<Map<String, dynamic>> parseLsOutput(String output, String basePath) {
    List<Map<String, dynamic>> entries = [];
    final lines = output.split('\n');
    for (var line in lines) {
      if (line.trim().isEmpty || line.startsWith('total')) continue;

      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 9) continue;

      String inode = parts[0];
      String permissions = parts[1];
      String name = parts.sublist(8).join(' ');
      String type = _determineType(permissions[0]);
      String? target;

      if (type == 'Symlink' && name.contains(' -> ')) {
        final split = name.split(' -> ');
        name = split[0].trim();
        target = split[1].trim();
      }

      if (name == '.' || name == '..') continue;

      entries.add({'inode': inode, 'name': name, 'type': type, 'target': target});
    }
    return entries;
  }

  Map<String, String> parseDuOutput(String output) {
    Map<String, String> sizeMap = {};
    final lines = output.split('\n');
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      final parts = line.trim().split('\t');
      if (parts.length != 2) continue;
      String size = parts[0];
      String path = parts[1];
      sizeMap[path] = size;
    }
    return sizeMap;
  }

  String _determineType(String char) {
    switch (char) {
      case 'd':
        return 'Directory';
      case '-':
        return 'File';
      case 'l':
        return 'Symlink';
      case 'c':
        return 'Character Device';
      case 'b':
        return 'Block Device';
      case 's':
        return 'Socket';
      case 'p':
        return 'Named Pipe';
      default:
        return 'Unknown';
    }
  }

  int parseSizeToBytes(String sizeString) {
    if (sizeString.toLowerCase() == 'unknown') return 0;
    final sizeRegex = RegExp(r'([\d.]+)([KMGTP]?)');
    final match = sizeRegex.firstMatch(sizeString);
    if (match == null) return 0;
    double size = double.tryParse(match.group(1)!) ?? 0;
    String unit = match.group(2)!.toUpperCase();
    switch (unit) {
      case 'K':
        return (size * 1024).round();
      case 'M':
        return (size * 1024 * 1024).round();
      case 'G':
        return (size * 1024 * 1024 * 1024).round();
      case 'T':
        return (size * 1024 * 1024 * 1024 * 1024).round();
      default:
        return size.round();
    }
  }

  List<_TreemapEntry> flattenTree(TreeNode root) {
    List<_TreemapEntry> allNodes = [];
    void traverse(TreeNode node, String? parentFolderPath) {
      if (node.type != 'Directory' && node.type != 'Unknown') {
        if (node.size == 0 || node.size.isNaN || node.size < 0) {
          // skip
        } else {
          String immediateParent = parentFolderPath ?? '';
          if (!parentFolderColorMap.containsKey(immediateParent)) {
            int idx = parentFolderColorMap.length % colorPalette.length;
            parentFolderColorMap[immediateParent] = colorPalette[idx];
          }
          int colorIdx = colorPalette.indexOf(parentFolderColorMap[immediateParent]!);
          allNodes.add(_TreemapEntry(node: node, colorIdx: colorIdx));
        }
      }
      // Traverse children in order (they have already been sorted by size)
      for (var child in node.children) {
        traverse(child, node.fullPath);
      }
    }
    traverse(root, null);
    return allNodes;
  }

  List<TreeNode> pathToNodeNodes(TreeNode root, TreeNode target) {
    List<TreeNode> path = [];
    bool helper(TreeNode node) {
      if (node == target) {
        path.add(node);
        return true;
      }
      for (var child in node.children) {
        if (helper(child)) {
          path.add(node);
          return true;
        }
      }
      return false;
    }
    helper(root);
    return path.reversed.toList();
  }

  void onTreemapTap(_TreemapEntry entry) {
    setState(() {
      selectedNode = entry.node;
      expandedPaths.clear();
      if (rootNode != null) {
        List<TreeNode> nodePath = pathToNodeNodes(rootNode!, entry.node);
        for (final node in nodePath) {
          if (node.type == 'Directory') {
            expandedPaths.add(node.fullPath ?? node.name);
          }
        }
      }
      explorerRefresh++;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = explorerKeys[entry.node.fullPath ?? entry.node.name];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: 0.2,
        );
      }
    });
  }

  Widget buildExplorer(TreeNode? node) {
    if (node == null) return const SizedBox();
    final nodeKey = explorerKeys[node.fullPath ?? node.name] ?? GlobalKey();
    explorerKeys[node.fullPath ?? node.name] = nodeKey;

    String displayLabel = _basename(node.fullPath ?? node.name);

    // Show symlink as: (Symlink) file -> /target/path
    if (node.type == 'Symlink') {
      displayLabel = '(Symlink) $displayLabel -> ${node.target ?? "Unknown"}';
    }
    // Show duplicate as: (Duplicate) file -> /first/path/with/same/inode
    else if (node.type == 'Duplicate') {
      displayLabel = '(Duplicate) $displayLabel -> ${node.target ?? "Unknown"}';
    }

    // Styling: folders bold, symlinks/duplicates italic
    TextStyle style = TextStyle(
      fontSize: 14,
      fontWeight: node.type == 'Directory' ? FontWeight.bold : FontWeight.normal,
      fontStyle: (node.type == 'Symlink' || node.type == 'Duplicate')
          ? FontStyle.italic
          : FontStyle.normal,
      color: (node.type == 'Symlink' || node.type == 'Duplicate')
          ? Colors.teal
          : null,
    );

    if (node.type != 'Directory' && node.type != 'Unknown') {
      return ListTile(
        key: nodeKey,
        dense: true,
        title: Text(displayLabel, style: style),
        selected: node == selectedNode,
        onTap: () {
          setState(() {
            selectedNode = node;
          });
        },
      );
    }
    bool initiallyExpanded = expandedPaths.contains(node.fullPath);
    return ExpansionTile(
      key: Key('${node.fullPath}-$initiallyExpanded'),
      title: Text(
        node.fullPath == scanRoot
            ? _basename(scanRoot)
            : _basename(node.fullPath ?? node.name),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      initiallyExpanded: initiallyExpanded,
      children: node.children.map((child) => buildExplorer(child)).toList(),
      onExpansionChanged: (expanded) {
        setState(() {
          if (expanded) {
            expandedPaths.add(node.fullPath ?? node.name);
          } else {
            expandedPaths.remove(node.fullPath ?? node.name);
          }
        });
      },
    );
  }

  String _basename(String path) {
    var segs = path.split('/');
    for (int i = segs.length - 1; i >= 0; i--) {
      if (segs[i].isNotEmpty) return segs[i];
    }
    return path;
  }

  String _relativePath(String path, String base) {
    if (path == base) return '.';
    if (!base.endsWith('/')) base = '$base/';
    if (path.startsWith(base)) {
      return path.substring(base.length);
    }
    return path;
  }

  // --- Fullscreen logic: catch escape key and Android back ---
  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  // Handle Android back (pop out of fullscreen)
  Future<bool> _onWillPop() async {
    if (isFullscreen) {
      setState(() {
        isFullscreen = false;
      });
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: RawKeyboardListener(
        focusNode: _focusNode,
        onKey: (event) {
          if (isFullscreen && event.isKeyPressed(LogicalKeyboardKey.escape)) {
            setState(() {
              isFullscreen = false;
            });
          }
        },
        child: Scaffold(
          appBar: isFullscreen
              ? null
              : AppBar(
            title: const Text("ADirStat",
                style: TextStyle(fontSize: 20)),
            actions: [
              IconButton(
                icon: Icon(Icons.fullscreen),
                tooltip: "Fullscreen",
                onPressed: (rootNode == null)
                    ? null
                    : () => setState(() => isFullscreen = true),
              ),
            ],
            toolbarHeight: 38,
            elevation: 1,
          ),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: isFullscreen
                ? _buildMainView()
                : Column(
              children: [
                // Path input and Start Scan on one line
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pathController,
                        decoration: const InputDecoration(
                          labelText: 'Enter Start Path',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                        ),
                        style: const TextStyle(fontSize: 15),
                        onSubmitted: (_) => startScan(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: isScanning ? null : startScan,
                      child: const Text('Start Scan'),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                isScanning ? const LinearProgressIndicator() : const SizedBox(),
                const SizedBox(height: 8),
                Expanded(child: _buildMainView()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainView() {
    if (rootNode == null) {
      if (isScanning) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Scanning ${scanningDirRelativePath.isEmpty ? "." : scanningDirRelativePath}...',
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
        );
      } else {
        return const Center(child: Text('No data to display'));
      }
    }
    return Row(
      children: [
        // Explorer on left
        Container(
          width: 260,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ListView(
            key: ValueKey(explorerRefresh),
            controller: explorerScrollController,
            children: [buildExplorer(rootNode)],
          ),
        ),
        const SizedBox(width: 8),
        // Treemap on right
        Expanded(
          child: Builder(
            builder: (context) {
              List<_TreemapEntry> allNodes = [];
              allNodes = flattenTree(rootNode!);
              if (allNodes.isEmpty) {
                return const Center(child: Text('No files to display.'));
              }
              return SfTreemap(
                dataCount: allNodes.length,
                weightValueMapper: (int index) =>
                    allNodes[index].node.size.toDouble(),
                levels: [
                  TreemapLevel(
                    groupMapper: (int index) =>
                    allNodes[index].node.fullPath ??
                        allNodes[index].node.name,
                    colorValueMapper: (TreemapTile tile) {
                      final entry = allNodes[tile.indices[0]];
                      return colorPalette[
                      entry.colorIdx % colorPalette.length];
                    },
                    labelBuilder: (BuildContext context, TreemapTile tile) {
                      return const SizedBox.shrink();
                    },
                    padding: const EdgeInsets.all(1),
                    tooltipBuilder: (context, tile) {
                      final node = allNodes[tile.indices[0]].node;
                      return Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          'Path: ${node.fullPath}\nSize: ${bytesToHuman(node.size)}',
                        ),
                      );
                    },
                  ),
                ],
                onSelectionChanged: (TreemapTile tile) {
                  onTreemapTap(allNodes[tile.indices[0]]);
                },
                selectionSettings: const TreemapSelectionSettings(
                  color: Color(0x33000000),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TreemapEntry {
  final TreeNode node;
  final int colorIdx;
  _TreemapEntry({required this.node, required this.colorIdx});
}

class TreeNode {
  String name;
  int size;
  String type;
  String? target;
  String? fullPath;
  String? inode;
  List<TreeNode> children;

  TreeNode({
    required this.name,
    required this.size,
    required this.type,
    this.target,
    this.fullPath,
    this.children = const [],
    this.inode,
  });
}