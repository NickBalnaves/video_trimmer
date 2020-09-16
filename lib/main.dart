import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_trimmer_example/trim_editor_painter.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: HomePage(),
      );
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  double _startValue = 0.0;
  double _endValue = 0.0;
  File _videoFile;
  double _videoStartPos = 0.0;
  double _videoEndPos = 0.0;
  bool _progressVisibility = false;
  bool _isPlaying = false;
  double _thumbnailViewerW = 0.0;
  double _thumbnailViewerH = 0.0;

  double viewerHeight = 50.0;
  BoxFit fit = BoxFit.fitHeight;
  Duration maxVideoLength = Duration(milliseconds: 0);
  double circleSize = 5.0;
  double circleSizeOnDrag = 8.0;
  Color circlePaintColor = Colors.white;
  Color borderPaintColor = Colors.white;
  Color scrubberPaintColor = Colors.white;
  int thumbnailQuality = 75;

  bool _canUpdateStart = true;
  bool _isLeftDrag = true;

  Offset _startPos = Offset(0, 0);
  Offset _endPos = Offset(0, 0);

  double _startFraction = 0.0;
  double _endFraction = 1.0;

  int _videoDuration = 0;
  int _currentPosition = 0;

  int _numberOfThumbnails = 5;

  double _circleSize = 0.5;

  double fraction;
  double maxLengthPixels;

  Animation<double> _scrubberAnimation;
  AnimationController _animationController;
  Tween<double> _linearTween;

  VideoPlayerController _videoPlayerController;
  final FlutterFFmpeg _flutterFFmpeg = FlutterFFmpeg();

  Stream<List<Uint8List>> generateThumbnail() async* {
    List<Uint8List> _byteList = [];

    for (int i = 1; i <= _numberOfThumbnails; i++) {
      _byteList.add(
        await VideoThumbnail.thumbnailData(
          video: _videoFile.path,
          imageFormat: ImageFormat.JPEG,
          timeMs: (_videoDuration / _numberOfThumbnails * i).toInt(),
          quality: 50,
        ),
      );

      yield _byteList;
    }
  }

  void _setVideoStartPosition(DragUpdateDetails details) async {
    if (!(_startPos.dx + details.delta.dx < 0) &&
        !(_startPos.dx + details.delta.dx > _thumbnailViewerW) &&
        !(_startPos.dx + details.delta.dx > _endPos.dx)) {
      if (maxLengthPixels != null) {
        if (!(_endPos.dx - _startPos.dx - details.delta.dx > maxLengthPixels)) {
          setState(() {
            if (!(_startPos.dx + details.delta.dx < 0))
              _startPos += details.delta;

            _startFraction = (_startPos.dx / _thumbnailViewerW);

            _videoStartPos = _videoDuration * _startFraction;
            _startValue = _videoStartPos;
          });
          await _videoPlayerController.pause();
          await _videoPlayerController.seekTo(
            Duration(milliseconds: _videoStartPos.toInt()),
          );
          _linearTween.begin = _startPos.dx;
          _animationController.duration =
              Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
          _animationController.reset();
        }
      } else {
        setState(() {
          if (!(_startPos.dx + details.delta.dx < 0))
            _startPos += details.delta;

          _startFraction = (_startPos.dx / _thumbnailViewerW);

          _videoStartPos = _videoDuration * _startFraction;
          _startValue = _videoStartPos;
        });
        await _videoPlayerController.pause();
        await _videoPlayerController
            .seekTo(Duration(milliseconds: _videoStartPos.toInt()));
        _linearTween.begin = _startPos.dx;
        _animationController.duration =
            Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
        _animationController.reset();
      }
    }
  }

  void _setVideoEndPosition(DragUpdateDetails details) async {
    if (!(_endPos.dx + details.delta.dx > _thumbnailViewerW) &&
        !(_endPos.dx + details.delta.dx < 0) &&
        !(_endPos.dx + details.delta.dx < _startPos.dx)) {
      if (maxLengthPixels != null) {
        if (!(_endPos.dx - _startPos.dx + details.delta.dx > maxLengthPixels)) {
          setState(() {
            _endPos += details.delta;
            _endFraction = _endPos.dx / _thumbnailViewerW;

            _videoEndPos = _videoDuration * _endFraction;
            _endValue = _videoEndPos;
          });
          await _videoPlayerController.pause();
          await _videoPlayerController
              .seekTo(Duration(milliseconds: _videoEndPos.toInt()));
          _linearTween.end = _endPos.dx;
          _animationController.duration =
              Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
          _animationController.reset();
        }
      } else {
        setState(() {
          _endPos += details.delta;
          _endFraction = _endPos.dx / _thumbnailViewerW;
          _videoEndPos = _videoDuration * _endFraction;
          _endValue = _videoEndPos;
        });
        await _videoPlayerController.pause();
        await _videoPlayerController
            .seekTo(Duration(milliseconds: _videoEndPos.toInt()));
        _linearTween.end = _endPos.dx;
        _animationController.duration =
            Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
        _animationController.reset();
      }
    }
  }

  Future<void> saveTrimmedVideo({
    @required double startValue,
    @required double endValue,
  }) async {
    setState(() => _progressVisibility = true);

    final String _videoPath = _videoFile.path;
    final String _videoName = basename(_videoPath).split('.')[0];

    Duration startPoint = Duration(milliseconds: startValue.toInt());
    Duration endPoint = Duration(milliseconds: endValue.toInt());

    await _flutterFFmpeg
        .execute(
            '-i "$_videoPath" -ss $startPoint -t ${endPoint - startPoint} -c:a copy -c:v copy "${await getApplicationDocumentsDirectory()}/$_videoName.mp4"')
        .whenComplete(() {})
        .catchError((_) {});
    setState(() => _progressVisibility = false);
  }

  Future<void> onLoadVideo() async {
    File file = await ImagePicker.pickVideo(
      source: ImageSource.gallery,
    );
    if (file != null) {
      setState(
        () {
          _videoFile = file;
          _videoPlayerController = VideoPlayerController.file(file);
        },
      );
      await _videoPlayerController.initialize();
      _circleSize = circleSize;
      _thumbnailViewerH = viewerHeight;
      _thumbnailViewerW = (50.0 * 8) ~/ _thumbnailViewerH * _thumbnailViewerH;

      Duration totalDuration = _videoPlayerController.value.duration;

      if (maxVideoLength > Duration(milliseconds: 0) &&
          maxVideoLength < totalDuration) {
        if (maxVideoLength < totalDuration) {
          fraction =
              maxVideoLength.inMilliseconds / totalDuration.inMilliseconds;

          maxLengthPixels = _thumbnailViewerW * fraction;
        }
      }

      if (_videoFile != null) {
        _videoPlayerController.addListener(() {
          final isPlaying = _videoPlayerController.value.isPlaying;

          if (isPlaying) {
            _isPlaying = true;
            setState(
              () {
                _currentPosition =
                    _videoPlayerController.value.position.inMilliseconds;

                if (_currentPosition > _videoEndPos.toInt()) {
                  _isPlaying = false;
                  _videoPlayerController.pause();
                  _animationController.stop();
                } else {
                  if (!_animationController.isAnimating) {
                    _isPlaying = true;
                    _animationController.forward();
                  }
                }
              },
            );
          } else {
            if (_videoPlayerController.value.initialized) {
              if (_animationController != null) {
                if ((_scrubberAnimation.value).toInt() ==
                    (_endPos.dx).toInt()) {
                  _animationController.reset();
                }
                _animationController.stop();
                _isPlaying = false;
              }
            }
          }
        });

        _videoPlayerController.setVolume(1.0);
        _videoDuration = _videoPlayerController.value.duration.inMilliseconds;

        _videoEndPos = fraction != null
            ? _videoDuration.toDouble() * fraction
            : _videoDuration.toDouble();

        setState(() => _endValue = _videoEndPos);
      }
      _endPos = Offset(
        maxLengthPixels != null ? maxLengthPixels : _thumbnailViewerW,
        _thumbnailViewerH,
      );

      _linearTween = Tween(begin: _startPos.dx, end: _endPos.dx);

      _animationController = AnimationController(
        vsync: this,
        duration:
            Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt()),
      );

      _scrubberAnimation =
          Tween(begin: 0.0, end: 0.0).animate(_animationController)
            ..addListener(() {
              setState(() {});
            })
            ..addStatusListener(
              (status) {
                if (status == AnimationStatus.completed) {
                  _animationController.stop();
                }
              },
            );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(Icons.save, color: Colors.white),
            onPressed: _progressVisibility
                ? null
                : () async {
                    await saveTrimmedVideo(
                      startValue: _startValue,
                      endValue: _endValue,
                    );
                    _scaffoldKey.currentState.showSnackBar(
                      SnackBar(
                        content: Text('Trimmed video saved'),
                      ),
                    );
                  },
          ),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          if (_videoPlayerController != null) ...[
            Visibility(
              visible: _progressVisibility,
              child: LinearProgressIndicator(
                backgroundColor: Colors.red,
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _videoPlayerController.value.aspectRatio,
                  child: _videoPlayerController.value.initialized
                      ? VideoPlayer(_videoPlayerController)
                      : Container(
                          child: Center(
                            child: CircularProgressIndicator(
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            Center(
              child: GestureDetector(
                onHorizontalDragStart: (DragStartDetails details) {
                  if (_endPos.dx >= _startPos.dx) {
                    if ((_startPos.dx - details.localPosition.dx).abs() >
                        (_endPos.dx - details.localPosition.dx).abs()) {
                      setState(() => _canUpdateStart = false);
                    } else {
                      setState(() => _canUpdateStart = true);
                    }
                  } else {
                    if (_startPos.dx > details.localPosition.dx) {
                      _isLeftDrag = true;
                    } else {
                      _isLeftDrag = false;
                    }
                  }
                },
                onHorizontalDragEnd: (DragEndDetails details) {
                  setState(() {
                    _circleSize = circleSize;
                  });
                },
                onHorizontalDragUpdate: (DragUpdateDetails details) {
                  _circleSize = circleSizeOnDrag;

                  if (_endPos.dx >= _startPos.dx) {
                    _isLeftDrag = false;
                    if (_canUpdateStart &&
                        _startPos.dx + details.delta.dx > 0) {
                      _isLeftDrag = false; // To prevent from scrolling over
                      _setVideoStartPosition(details);
                    } else if (!_canUpdateStart &&
                        _endPos.dx + details.delta.dx < _thumbnailViewerW) {
                      _isLeftDrag = true; // To prevent from scrolling over
                      _setVideoEndPosition(details);
                    }
                  } else {
                    if (_isLeftDrag && _startPos.dx + details.delta.dx > 0) {
                      _setVideoStartPosition(details);
                    } else if (!_isLeftDrag &&
                        _endPos.dx + details.delta.dx < _thumbnailViewerW) {
                      _setVideoEndPosition(details);
                    }
                  }
                },
                child: Column(
                  children: [
                    Container(
                      width: _thumbnailViewerW,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text(
                              Duration(milliseconds: _videoStartPos.toInt())
                                  .toString()
                                  .split('.')[0],
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              Duration(milliseconds: _videoEndPos.toInt())
                                  .toString()
                                  .split('.')[0],
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_videoPlayerController != null &&
                        _scrubberAnimation != null)
                      CustomPaint(
                        foregroundPainter: TrimEditorPainter(
                          startPos: _startPos,
                          endPos: _endPos,
                          scrubberAnimationDx: _scrubberAnimation.value,
                          circleSize: _circleSize,
                          circlePaintColor: circlePaintColor,
                          borderPaintColor: borderPaintColor,
                          scrubberPaintColor: scrubberPaintColor,
                        ),
                        child: Container(
                          color: Colors.grey[900],
                          height: _thumbnailViewerH,
                          width: _thumbnailViewerW,
                          child: StreamBuilder(
                            stream: generateThumbnail(),
                            builder: (context, snapshot) => snapshot.hasData
                                ? ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: snapshot.data.length,
                                    itemBuilder: (context, index) => Container(
                                      height: _thumbnailViewerH,
                                      width: _thumbnailViewerH,
                                      child: Image(
                                        image:
                                            MemoryImage(snapshot.data[index]),
                                        fit: fit,
                                      ),
                                    ),
                                  )
                                : Container(
                                    color: Colors.grey[900],
                                    height: _thumbnailViewerH,
                                    width: double.maxFinite,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            FlatButton(
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                size: 50.0,
              ),
              onPressed: () async {
                bool playbackState;
                if (_videoPlayerController.value.isPlaying) {
                  await _videoPlayerController.pause();
                  playbackState = false;
                } else {
                  if (_videoPlayerController.value.position.inMilliseconds >=
                      _endValue.toInt()) {
                    await _videoPlayerController
                        .seekTo(Duration(milliseconds: _startValue.toInt()));
                    await _videoPlayerController.play();
                    playbackState = true;
                  } else {
                    await _videoPlayerController.play();
                    playbackState = true;
                  }
                }
                setState(() => _isPlaying = playbackState);
              },
            ),
          ],
          Center(
            child: RaisedButton(
              child: Text("LOAD VIDEO"),
              onPressed: () async => onLoadVideo(),
            ),
          ),
        ],
      ),
    );
  }
}
