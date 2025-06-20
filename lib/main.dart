import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() => runApp(CommandApp());

class CommandApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: VoiceCommandScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VoiceCommandScreen extends StatefulWidget {
  @override
  _VoiceCommandScreenState createState() => _VoiceCommandScreenState();
}

class _VoiceCommandScreenState extends State<VoiceCommandScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _commandMode = false;
  String _lastWords = '';
  String _responseText = '';
  int _errorCount = 0;
  bool _permissionGranted = false;
  Timer? _restartTimer;
  bool _userRequestedStop = false;
  DateTime? _lastRestartTime;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      bool initialized = await _speech.initialize(
        onStatus: (status) {
          print('Trạng thái nhận dạng: $status');
          setState(() {
            _isListening = status == stt.SpeechToText.listeningStatus;

            // Tự động khởi động lại nếu không phải do người dùng dừng
            if (!_userRequestedStop &&
                (status == stt.SpeechToText.doneStatus ||
                    status == stt.SpeechToText.notListeningStatus) &&
                _permissionGranted) {
              _scheduleRestart();
            }
          });
        },
        onError: (error) {
          print('Lỗi nhận dạng: ${error.errorMsg}');
          _handleError(error.errorMsg);
        },
      );

      if (initialized) {
        setState(() {
          _permissionGranted = true;
        });
        _startContinuousListening();
      } else {
        setState(() => _responseText = 'Không thể khởi tạo nhận dạng giọng nói');
        Future.delayed(Duration(seconds: 2), _initSpeech);
      }
    } catch (e) {
      print('Lỗi khởi tạo: $e');
      setState(() => _responseText = 'Lỗi khởi tạo: $e');
      Future.delayed(Duration(seconds: 2), _initSpeech);
    }
  }

  void _startContinuousListening() {
    if (_permissionGranted && !_speech.isListening && !_userRequestedStop) {
      print('Bắt đầu nghe...');
      _speech.listen(
        onResult: (result) {
          setState(() {
            _lastWords = result.recognizedWords;
            _errorCount = 0;

            if (result.finalResult) {
              _processSpeech(_lastWords);
            }
          });
        },
        listenFor: Duration(hours: 1), // Nghe trong thời gian dài
        pauseFor: Duration(seconds: 2), // Thời gian chờ ngắn
        partialResults: true,
        localeId: 'vi_VN',
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
        onSoundLevelChange: (level) {
          // Xử lý mức độ âm thanh nếu cần
        },
      ).catchError((error) {
        print('Lỗi khi nghe: $error');
        _handleError(error.toString());
      });
    }
  }

  void _scheduleRestart() {
    // Tránh khởi động lại quá nhanh
    final now = DateTime.now();
    if (_lastRestartTime != null &&
        now.difference(_lastRestartTime!).inMilliseconds < 300) {
      return;
    }
    _lastRestartTime = now;

    _restartTimer?.cancel();
    _restartTimer = Timer(Duration(milliseconds: 300), () {
      if (!_userRequestedStop && _permissionGranted && !_speech.isListening) {
        print('Khởi động lại quá trình nghe...');
        _startContinuousListening();
      }
    });
  }

  void _handleError(String errorMsg) {
    print('Xử lý lỗi: $errorMsg');
    setState(() => _errorCount++);

    if (_errorCount < 10) {
      _scheduleRestart();
    } else {
      setState(() => _responseText = 'Lỗi nghiêm trọng: $errorMsg');
      // Thử khởi tạo lại toàn bộ sau 5 giây
      Future.delayed(Duration(seconds: 5), () {
        _errorCount = 0;
        _initSpeech();
      });
    }
  }

  void _processSpeech(String words) {
    if (!_commandMode) {
      if (words.toLowerCase().contains('hello')) {
        setState(() {
          _commandMode = true;
          _responseText = 'Chế độ AI đã kích hoạt! Nói lệnh của bạn...';
        });
      }
    } else {
      if (words.trim().isNotEmpty) {
        _sendToOpenAI(words);
      }
    }
  }

  Future<void> _sendToOpenAI(String prompt) async {
    const apiKey = 'YOUR_API_KEY'; // Thay thế bằng API key thực
    const apiUrl = 'https://api.openai.com/v1/chat/completions';

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'system',
              'content': 'Bạn là trợ lý ảo. Hãy trả lời ngắn gọn, rõ ràng bằng tiếng Việt'
            },
            {'role': 'user', 'content': prompt}
          ],
          'max_tokens': 200,
          'temperature': 0.7,
        }),
      ).timeout(Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _responseText = data['choices'][0]['message']['content']);
      } else {
        setState(() => _responseText = 'Lỗi API: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _responseText = 'Kết nối lỗi: $e');
    } finally {
      // Đảm bảo tiếp tục nghe sau khi xử lý xong
      if (!_userRequestedStop) {
        _scheduleRestart();
      }
    }
  }

  void _toggleListening() {
    setState(() {
      _userRequestedStop = !_userRequestedStop;
      if (_userRequestedStop) {
        _speech.stop();
        _restartTimer?.cancel();
        setState(() => _responseText = 'Mic đã tắt');
      } else {
        _startContinuousListening();
        setState(() => _responseText = 'Mic đã bật');
      }
    });
  }

  @override
  void dispose() {
    _userRequestedStop = true;
    _restartTimer?.cancel();
    _speech.stop();
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Trợ Lý Ảo AI - Mic Luôn Bật'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_userRequestedStop ? Icons.mic_off : Icons.mic, size: 30),
            onPressed: _toggleListening,
            tooltip: _userRequestedStop ? 'Bật mic' : 'Tắt mic',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Phần hiển thị trạng thái
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isListening ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isListening ? Icons.mic : Icons.mic_off,
                    color: _isListening ? Colors.green : Colors.red,
                    size: 30,
                  ),
                  SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isListening ? 'ĐANG NGHE' : 'TẠM DỪNG',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _isListening ? Colors.green : Colors.red,
                        ),
                      ),
                      Text(
                        'Chế độ: ${_commandMode ? 'AI ĐÃ KÍCH HOẠT' : 'CHỜ LỆNH "HELLO"'}',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // Phần hiển thị kết quả nhận dạng
            Text('Lời nói nhận dạng:', style: TextStyle(fontWeight: FontWeight.bold)),
            Container(
              padding: EdgeInsets.all(12),
              margin: EdgeInsets.only(top: 8, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                border: Border.all(color: Colors.blue),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _lastWords,
                style: TextStyle(fontSize: 16),
              ),
            ),

            // Phần hiển thị phản hồi AI
            Text('Phản hồi từ AI:', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Container(
                padding: EdgeInsets.all(12),
                margin: EdgeInsets.only(top: 8, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.05),
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _responseText,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),

            // Nút điều khiển
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(Icons.smart_toy),
                  label: Text('BẬT CHẾ ĐỘ AI'),
                  onPressed: () => setState(() {
                    _commandMode = true;
                    _responseText = 'Chế độ AI đã kích hoạt! Nói lệnh của bạn...';
                  }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _commandMode ? Colors.blue : Colors.grey,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  ),
                ),
                ElevatedButton.icon(
                  icon: Icon(_userRequestedStop ? Icons.mic : Icons.mic_off),
                  label: Text(_userRequestedStop ? 'BẬT MIC' : 'TẮT MIC'),
                  onPressed: _toggleListening,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _userRequestedStop ? Colors.green : Colors.red,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}