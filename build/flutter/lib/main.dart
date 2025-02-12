import 'dart:async';
import 'dart:io';

import 'package:flet/flet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:serious_python/serious_python.dart';
import 'package:url_strategy/url_strategy.dart';
import 'package:window_manager/window_manager.dart';



const bool isProduction = bool.fromEnvironment('dart.vm.product');

const assetPath = "app/app.zip";
const pythonModuleName = "main";
final hideLoadingPage =
    bool.tryParse("True".toLowerCase()) ??
        true;
const errorExitCode = 100;

List<CreateControlFactory> createControlFactories = [

];

const pythonScript = """
import certifi, os, runpy, socket, sys, traceback

os.environ["REQUESTS_CA_BUNDLE"] = certifi.where()
os.environ["SSL_CERT_FILE"] = certifi.where()

# fix for cryptography package
os.environ["CRYPTOGRAPHY_OPENSSL_NO_LEGACY"] = "1"

# fix for: https://github.com/flet-dev/serious-python/issues/85#issuecomment-2065000974
os.environ["OPENBLAS_NUM_THREADS"] = "1"

if os.getenv("FLET_PLATFORM") == "android":
    import ssl

    def create_default_context(
        purpose=ssl.Purpose.SERVER_AUTH, *, cafile=None, capath=None, cadata=None
    ):
        return ssl.create_default_context(
            purpose=purpose, cafile=certifi.where(), capath=capath, cadata=cadata
        )

    ssl._create_default_https_context = create_default_context

out_file = open("{outLogFilename}", "w+", buffering=1)

callback_socket_addr = os.getenv("FLET_PYTHON_CALLBACK_SOCKET_ADDR")
if ":" in callback_socket_addr:
    addr, port = callback_socket_addr.split(":")
    callback_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    callback_socket.connect((addr, int(port)))
else:
    callback_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    callback_socket.connect(callback_socket_addr)

sys.stdout = sys.stderr = out_file

def flet_exit(code=0):
    callback_socket.sendall(str(code).encode())
    out_file.close()
    callback_socket.close()

sys.exit = flet_exit

ex = None
try:
    sys.argv = {argv}
    runpy.run_module("{module_name}", run_name="__main__")
except Exception as e:
    ex = e
    traceback.print_exception(e)

sys.exit(0 if ex is None else $errorExitCode)
""";

String outLogFilename = "";

// global vars
String pageUrl = "";
String assetsDir = "";
String appDir = "";
Map<String, String> environmentVariables = {};

void main(List<String> args) async {
  if (!args.contains("--debug")) {
    // ignore: avoid_returning_null_for_void
    debugPrint = (String? message, {int? wrapWidth}) => null;
  }

  await setupDesktop();

  

  runApp(FutureBuilder(
      future: prepareApp(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.hasData) {
          // OK - start Python program
          return kIsWeb
              ? FletApp(
                  pageUrl: pageUrl,
                  assetsDir: assetsDir,
                  hideLoadingPage: hideLoadingPage,
                  createControlFactories: createControlFactories)
              : FutureBuilder(
                  future: runPythonApp(args),
                  builder:
                      (BuildContext context, AsyncSnapshot<String?> snapshot) {
                    if (snapshot.hasData || snapshot.hasError) {
                      // error or premature finish
                      return MaterialApp(
                        home: ErrorScreen(
                            title: "Error running app",
                            text: snapshot.data ?? snapshot.error.toString()),
                      );
                    } else {
                      // no result of error
                      return FletApp(
                          pageUrl: pageUrl,
                          assetsDir: assetsDir,
                          hideLoadingPage: hideLoadingPage,
                          createControlFactories: createControlFactories);
                    }
                  });
        } else if (snapshot.hasError) {
          // error
          return MaterialApp(
              home: ErrorScreen(
                  title: "Error starting app",
                  text: snapshot.error.toString()));
        } else {
          // loading
          return const MaterialApp(home: BlankScreen());
        }
      }));
}

Future prepareApp() async {
  if (kIsWeb) {
    // web mode - connect via HTTP
    pageUrl = Uri.base.toString();
    var routeUrlStrategy = getFletRouteUrlStrategy();
    if (routeUrlStrategy == "path") {
      setPathUrlStrategy();
    }
  } else {
    // extract app from asset
    appDir = await extractAssetZip(assetPath, checkHash: true);

    // set current directory to app path
    Directory.current = appDir;

    assetsDir = path.join(appDir, "assets");

    // configure apps DATA and TEMP directories
    WidgetsFlutterBinding.ensureInitialized();

    var appTempPath = (await path_provider.getApplicationCacheDirectory()).path;
    var appDataPath =
        (await path_provider.getApplicationDocumentsDirectory()).path;

    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      // append app name to the path and create dir
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      appDataPath = path.join(appDataPath, "flet", packageInfo.packageName);
      if (!await Directory(appDataPath).exists()) {
        await Directory(appDataPath).create(recursive: true);
      }
    }

    environmentVariables["FLET_APP_STORAGE_DATA"] = appDataPath;
    environmentVariables["FLET_APP_STORAGE_TEMP"] = appTempPath;

    outLogFilename = path.join(appTempPath, "console.log");
    environmentVariables["FLET_APP_CONSOLE"] = outLogFilename;

    environmentVariables["FLET_PLATFORM"] =
        defaultTargetPlatform.name.toLowerCase();

    if (defaultTargetPlatform == TargetPlatform.windows) {
      // use TCP on Windows
      var tcpPort = await getUnusedPort();
      pageUrl = "tcp://localhost:$tcpPort";
      environmentVariables["FLET_SERVER_PORT"] = tcpPort.toString();
    } else {
      // use UDS on other platforms
      pageUrl = "flet_$pid.sock";
      environmentVariables["FLET_SERVER_UDS_PATH"] = pageUrl;
    }
  }

  return "";
}

Future<String?> runPythonApp(List<String> args) async {
  var argvItems = args.map((a) => "\"${a.replaceAll('"', '\\"')}\"");
  var argv = "[${argvItems.isNotEmpty ? argvItems.join(',') : '""'}]";
  var script = pythonScript
      .replaceAll("{outLogFilename}", outLogFilename.replaceAll("\\", "\\\\"))
      .replaceAll('{module_name}', pythonModuleName)
      .replaceAll('{argv}', argv);

  var completer = Completer<String>();

  ServerSocket outSocketServer;
  String socketAddr = "";
  StringBuffer pythonOut = StringBuffer();

  if (defaultTargetPlatform == TargetPlatform.windows) {
    var tcpAddr = "127.0.0.1";
    outSocketServer = await ServerSocket.bind(tcpAddr, 0);
    debugPrint(
        'Python output TCP Server is listening on port ${outSocketServer.port}');
    socketAddr = "$tcpAddr:${outSocketServer.port}";
  } else {
    socketAddr = "stdout_$pid.sock";
    if (await File(socketAddr).exists()) {
      await File(socketAddr).delete();
    }
    outSocketServer = await ServerSocket.bind(
        InternetAddress(socketAddr, type: InternetAddressType.unix), 0);
    debugPrint('Python output Socket Server is listening on $socketAddr');
  }

  environmentVariables["FLET_PYTHON_CALLBACK_SOCKET_ADDR"] = socketAddr;

  void closeOutServer() async {
    outSocketServer.close();

    int exitCode = int.tryParse(pythonOut.toString().trim()) ?? 0;

    if (exitCode == errorExitCode) {
      var out = "";
      if (await File(outLogFilename).exists()) {
        out = await File(outLogFilename).readAsString();
      }
      completer.complete(out);
    } else {
      exit(exitCode);
    }
  }

  outSocketServer.listen((client) {
    debugPrint(
        'Connection from: ${client.remoteAddress.address}:${client.remotePort}');
    client.listen((data) {
      var s = String.fromCharCodes(data);
      pythonOut.write(s);
    }, onError: (error) {
      client.close();
      closeOutServer();
    }, onDone: () {
      client.close();
      closeOutServer();
    });
  });

  // run python async
  SeriousPython.runProgram(path.join(appDir, "$pythonModuleName.pyc"),
      script: script, environmentVariables: environmentVariables);

  // wait for client connection to close
  return completer.future;
}

class ErrorScreen extends StatelessWidget {
  final String title;
  final String text;

  const ErrorScreen({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
          child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                  icon: const Icon(
                    Icons.copy,
                    size: 16,
                  ),
                  label: const Text("Copy"),
                )
              ],
            ),
            Expanded(
                child: SingleChildScrollView(
              child: SelectableText(text,
                  style: Theme.of(context).textTheme.bodySmall),
            ))
          ],
        ),
      )),
    );
  }
}

class BlankScreen extends StatelessWidget {
  const BlankScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}

Future<int> getUnusedPort() {
  return ServerSocket.bind("127.0.0.1", 0).then((socket) {
    var port = socket.port;
    socket.close();
    return port;
  });
}

bool isDesktop() {
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);
}

Future setupDesktop() async {
  if (isDesktop()) {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();

    Map<String, String> env = Platform.environment;
    var hideWindowOnStart = env["FLET_HIDE_WINDOW_ON_START"];
    var hideAppOnStart = env["FLET_HIDE_APP_ON_START"];
    debugPrint("hideWindowOnStart: $hideWindowOnStart");
    debugPrint("hideAppOnStart: $hideAppOnStart");

    await windowManager.waitUntilReadyToShow(null, () async {
      if (hideWindowOnStart == null && hideAppOnStart == null) {
        await windowManager.show();
        await windowManager.focus();
      } else if (hideAppOnStart != null) {
        await windowManager.setSkipTaskbar(true);
      }
    });
  }
}
