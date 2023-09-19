import 'dart:async';
import 'dart:io';

import 'package:animated_check/animated_check.dart';
import 'package:animated_cross/animated_cross.dart';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

late List<CameraDescription> _cameras;
XFile? picture;

enum RequestState {
  idle,
  running,
  success,
  failed,
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();

  runApp(
    MaterialApp(
      title: 'CameraApp',
      debugShowCheckedModeBanner: false,
      home: const CameraApp(),
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.green,
        ),
      ),
    ),
  );
}

Future<Position> determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return Future.error('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    return Future.error(
        'Location permissions are permanently denied, cannot request permissions.');
  }
  return await Geolocator.getCurrentPosition();
}

class CameraApp extends StatefulWidget {
  const CameraApp({Key? key}) : super(key: key);

  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp>
    with SingleTickerProviderStateMixin {
  late CameraController cameraController;

  @override
  void initState() {
    super.initState();
    cameraController = CameraController(
      _cameras[0],
      ResolutionPreset.max,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    cameraController.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!cameraController.value.isInitialized) {
      return Container();
    }
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Center(
        child: CameraPreview(cameraController),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          picture = await cameraController.takePicture();
          setState(() {});
          showModalBottomSheet(
            showDragHandle: true,
            isScrollControlled: true,
            context: context,
            builder: (_) => MyBottomSheet(),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(25.0),
              ),
            ),
          );
        },
        child: const Icon(Icons.camera_alt_outlined),
      ),
    );
  }
}

class MyBottomSheet extends StatefulWidget {
  @override
  _MyBottomSheetState createState() => _MyBottomSheetState();
}

class _MyBottomSheetState extends State<MyBottomSheet>
    with SingleTickerProviderStateMixin {
  final commentController = TextEditingController();
  late AnimationController animationController;
  var animation;

  RequestState requestState = RequestState.idle;

  @override
  void initState() {
    super.initState();
    animationController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1));
    animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: animationController,
        curve: Curves.easeInOutQuart,
      ),
    );
  }

  sendData() async {
    setState(() {
      requestState = RequestState.running;
    });
    final position = await determinePosition();
    Dio dio = Dio();
    FormData formData = FormData.fromMap({
      'comment': commentController.text,
      'latitude': position.latitude.toString(),
      'longitude': position.longitude.toString(),
      'photo': kIsWeb?await MultipartFile.fromBytes(
        await picture!.readAsBytes(),
        filename: 'image.png',
        contentType: MediaType('image', 'png'),
      ):await MultipartFile.fromFile(picture!.path,filename: 'image.png', contentType: MediaType('image', 'png')),
    });
    // !!!
    // browser, android emulator = ok,
    // iphone = ok only if image hasn't good quality,
    // otherwise = Error in request: request entity too large
    // fixable with owning a server and configuring max request size PROBABLY =)
    // !!!
    try {
      Response response = await dio.post(
        "https://flutter-sandbox.free.beeceptor.com/upload_photo/",
        data: formData,
      );
      setState(() {
        requestState = RequestState.success;
      });
      animationController.forward();
      Timer(const Duration(milliseconds: 1500), () {
        Navigator.pop(context);
      });
    } catch (e) {
      setState(() {
        requestState = RequestState.failed;
      });
      animationController.forward();
      Timer(const Duration(milliseconds: 1500), () {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Ошибка при отправке запроса'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK'),
              )
            ],
          ),
        );
      });
    }
  }

  ElevatedButton responsiveSendCancelButton() {
    setState(() {});
    final text = commentController.text;
    if (text == "") {
      return ElevatedButton(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.all<Color>(Colors.orange),
        ),
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Text("Отмена"),
      );
    }
    return ElevatedButton(
      onPressed: () {
        sendData();
      },
      child: const Text("Отправить"),
    );
  }

  @override
  Widget build(BuildContext context) {
    commentController.addListener(() {
      responsiveSendCancelButton();
    });
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (requestState == RequestState.running)
            Container(
              padding: const EdgeInsets.all(100),
              child: const SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(),
              ),
            )
          else if (requestState == RequestState.success)
            AnimatedCheck(
              strokeWidth: 8,
              color: Colors.green,
              progress: animation,
              size: 200,
            )
          else if (requestState == RequestState.failed)
              AnimatedCross(
                strokeWidth: 8,
                color: Colors.red,
                progress: animation,
                size: 200,
              )
            else
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 250,
                          child: TextField(
                            controller: commentController,
                            decoration: const InputDecoration(
                              border: UnderlineInputBorder(),
                              labelText: "Комментарий",
                            ),
                          ),
                        ),
                        responsiveSendCancelButton(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        kIsWeb
                            ? Image.network(
                          picture!.path,
                          height: MediaQuery.of(context).size.height / 2,
                          width: MediaQuery.of(context).size.width / 2,
                        )
                            : Image.file(
                          File(picture!.path),
                          height: MediaQuery.of(context).size.height / 3,
                          width: MediaQuery.of(context).size.width / 3,
                        ),
                      ],
                    ),
                  )
                ],
              )
        ],
      ),
    );
  }

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }
}