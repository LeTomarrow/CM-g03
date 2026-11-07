import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/services/room_protocol.dart';
import 'package:what_did_you_press/services/game_protocol.dart';

class RoomConnection {
  const RoomConnection({required this.roomId, required this.code});
  final String roomId;
  final String code;
}

/// Local state derived from signaling membership and peer protocol messages.
class Room {
  const Room({
    required this.id,
    required this.code,
    required this.hostUid,
    required this.guestUid,
    required this.status,
    required this.expiresAt,
    required this.hostRole,
    this.rolesLocked = false,
  });
  final String id;
  final String code;
  final String hostUid;
  final String? guestUid;
  final String status;
  final DateTime expiresAt;
  final PlayerRole hostRole;

  /// The host keeps its role, as the operator of an open-world bomb.
  final bool rolesLocked;

  PlayerRole roleFor(String uid) {
    if (uid == hostUid) return hostRole;
    if (uid == guestUid) return hostRole.partner;
    throw StateError('Player is not a room member');
  }
}

/// Firestore is only a rendezvous/signaling mailbox. Lobby decisions are local
/// and exchanged through WebRTC; the host serializes all role/start decisions.
class RoomService {
  RoomService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final _events = StreamController<Room?>.broadcast();
  final _gameEvents = StreamController<GameMessage>.broadcast();
  DocumentReference<Map<String, dynamic>>? _ref;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  RTCPeerConnection? _peer;
  RTCDataChannel? _channel;
  RoomProtocol? _protocol;
  String? _hostUid;
  String? _guestUid;
  DateTime? _expiresAt;
  Room? _room;
  Future<void>? _signIn;
  Future<void> _signalQueue = Future.value();
  final Set<String> _remoteCandidates = {};
  bool _remoteDescriptionSet = false;
  bool _signalingClosed = false;
  bool _disposed = false;
  Timer? _connectionTimer;
  Timer? _startTimer;
  Completer<void>? _startAck;

  /// Keeps the host's role fixed, e.g. the operator of an open-world bomb.
  /// Guest swap requests are answered with the unchanged state.
  bool rolesLocked = false;

  String? get currentUserId => _auth.currentUser?.uid;
  bool get _isHost => _hostUid == currentUserId;
  bool get _connected =>
      _channel?.state == RTCDataChannelState.RTCDataChannelOpen;

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser != null) return;
    final pending = _signIn ??= _auth.signInAnonymously().then((_) {});
    try {
      await pending;
    } finally {
      if (identical(_signIn, pending)) _signIn = null;
    }
  }

  FirebaseException _error(String message) => FirebaseException(
    plugin: 'room',
    code: 'failed-precondition',
    message: message,
  );

  void _requireNewSession() {
    if (_ref != null || _disposed) {
      throw _error('Sai da sala atual antes de criar outra.');
    }
  }

  Future<RoomConnection> createRoom() async {
    _requireNewSession();
    await _ensureSignedIn();
    final random = Random.secure();
    for (var attempt = 0; attempt < 10; attempt++) {
      final code = (100000 + random.nextInt(900000)).toString();
      final session = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final ref = _firestore.collection('rooms').doc(code);
      final expiry = DateTime.now().add(const Duration(hours: 1));
      final created = await _firestore.runTransaction((tx) async {
        final snapshot = await tx.get(ref);
        if (snapshot.exists) return false;
        tx.set(ref, {
          'version': 1,
          'session': session,
          'hostUid': currentUserId,
          'guestUid': null,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiry),
          'offer': null,
          'answer': null,
          'hostCandidates': <dynamic>[],
          'guestCandidates': <dynamic>[],
        });
        return true;
      });
      if (!created) continue;
      await _begin(ref, session, currentUserId!, null, expiry);
      return RoomConnection(roomId: code, code: code);
    }
    throw _error('Não foi possível reservar um código. Tenta novamente.');
  }

  Future<RoomConnection> joinRoom(String code) async {
    _requireNewSession();
    code = code.trim();
    _validateRoomId(code);
    await _ensureSignedIn();
    final ref = _firestore.collection('rooms').doc(code);
    final data = await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final data = snapshot.data();
      if (data == null || data['version'] != 1) {
        throw _error('Sala não encontrada. Confirma o código.');
      }
      if ((data['expiresAt'] as Timestamp).toDate().isBefore(DateTime.now())) {
        throw _error('A sala expirou.');
      }
      if (data['hostUid'] == currentUserId) {
        throw _error('Já és o anfitrião desta sala.');
      }
      if (data['guestUid'] != null && data['guestUid'] != currentUserId) {
        throw _error('A sala está cheia.');
      }
      // Reusing a previously claimed slot would mix old ICE/SDP with a new peer.
      if (data['answer'] != null) {
        throw _error('Cria uma nova sala para voltar a ligar.');
      }
      tx.update(ref, {'guestUid': currentUserId});
      return data;
    });
    await _begin(
      ref,
      data['session'] as String,
      data['hostUid'] as String,
      currentUserId,
      (data['expiresAt'] as Timestamp).toDate(),
    );
    return RoomConnection(roomId: code, code: code);
  }

  Future<void> _begin(
    DocumentReference<Map<String, dynamic>> ref,
    String session,
    String host,
    String? guest,
    DateTime expiry,
  ) async {
    _ref = ref;
    _hostUid = host;
    _guestUid = guest;
    _expiresAt = expiry;
    _protocol = RoomProtocol(session: session, isHost: _isHost)
      ..locked = _isHost && rolesLocked;
    _emit();
    try {
      // For arbitrary networks configure a TURN relay; STUN alone is best effort.
      const stun = String.fromEnvironment(
        'WEBRTC_STUN_URL',
        defaultValue: 'stun:stun.l.google.com:19302',
      );
      const turn = String.fromEnvironment('WEBRTC_TURN_URL');
      _peer = await createPeerConnection({
        'iceServers': [
          {'urls': stun},
          if (turn.isNotEmpty)
            {
              'urls': turn,
              'username': const String.fromEnvironment('WEBRTC_TURN_USERNAME'),
              'credential': const String.fromEnvironment(
                'WEBRTC_TURN_CREDENTIAL',
              ),
            },
        ],
      });
      _peer!.onIceCandidate = (candidate) {
        if (candidate.candidate?.isNotEmpty != true || _signalingClosed) return;
        unawaited(
          ref
              .update({
                _isHost ? 'hostCandidates' : 'guestCandidates':
                    FieldValue.arrayUnion([candidate.toMap()]),
              })
              .catchError((Object error) {
                if (!_signalingClosed) _fail(error);
              }),
        );
      };
      _peer!.onDataChannel = _attachChannel;
      _peer!.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _fail(
            _error('A ligação entre jogadores falhou. Cria uma nova sala.'),
          );
        }
      };
      if (_isHost) {
        _attachChannel(
          await _peer!.createDataChannel(
            'room-v1',
            RTCDataChannelInit()..ordered = true,
          ),
        );
        final offer = await _peer!.createOffer();
        await _peer!.setLocalDescription(offer);
        await ref.update({'offer': offer.toMap()});
      }
      _subscription = ref.snapshots().listen(
        (snapshot) {
          _signalQueue = _signalQueue
              .then((_) => _readSignaling(snapshot))
              .catchError((Object error) => _fail(error));
        },
        onError: (Object error) {
          if (!_signalingClosed) _fail(error);
        },
      );
      _armConnectionTimeout();
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> _readSignaling(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (_disposed || _signalingClosed) return;
    final data = snapshot.data();
    if (data == null || data['session'] != _protocol!.session) {
      _fail(_error('O anfitrião encerrou a sala.'));
      return;
    }
    _guestUid = data['guestUid'] as String?;
    _armConnectionTimeout();
    _emit();
    final description = data[_isHost ? 'answer' : 'offer'];
    if (!_remoteDescriptionSet && description != null) {
      await _peer!.setRemoteDescription(
        RTCSessionDescription(
          description['sdp'] as String,
          description['type'] as String,
        ),
      );
      _remoteDescriptionSet = true;
      if (!_isHost) {
        final answer = await _peer!.createAnswer();
        await _peer!.setLocalDescription(answer);
        if (!_signalingClosed) await _ref!.update({'answer': answer.toMap()});
      }
    }
    if (!_remoteDescriptionSet) return;
    for (final candidate
        in data[_isHost ? 'guestCandidates' : 'hostCandidates'] as List) {
      final key = jsonEncode(candidate);
      if (!_remoteCandidates.add(key)) continue;
      await _peer!.addCandidate(
        RTCIceCandidate(
          candidate['candidate'] as String?,
          candidate['sdpMid'] as String?,
          candidate['sdpMLineIndex'] as int?,
        ),
      );
    }
  }

  void _armConnectionTimeout() {
    if (_guestUid == null || _connected) return;
    _connectionTimer ??= Timer(const Duration(seconds: 60), () {
      if (!_connected) {
        _fail(_error('A ligação demorou demasiado. Cria uma nova sala.'));
      }
    });
  }

  void _attachChannel(RTCDataChannel channel) {
    if (channel.label != 'room-v1') return;
    _channel = channel;
    channel.onMessage = (message) {
      if (message.isBinary || _disposed) return;
      try {
        try {
          _receive(RoomMessage.decode(message.text, _protocol!.session));
        } on FormatException {
          _gameEvents.add(GameMessage.decode(message.text, _protocol!.session));
        }
      } on FormatException {
        // Ignore malformed or unrelated packets; never infer identity from JSON.
      } catch (error) {
        _fail(error);
      }
    };
    channel.onDataChannelState = (state) {
      if (_disposed || _protocol?.phase == 'closed') return;
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _connectionTimer?.cancel();
        _protocol!.connected();
        _emit();
        _send(_isHost ? 'state' : 'hello');
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _fail(_error('O outro jogador desligou-se.'));
      }
    };
    // Native peers can deliver an already-open channel in onDataChannel.
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      channel.onDataChannelState?.call(RTCDataChannelState.RTCDataChannelOpen);
    }
  }

  void _send(String type) {
    if (!_connected) throw _error('Espera pela ligação ao outro jogador.');
    unawaited(
      _channel!
          .send(RTCDataChannelMessage(_protocol!.message(type).encode()))
          .catchError((Object error) => _fail(error)),
    );
  }

  void _receive(RoomMessage message) {
    final protocol = _protocol!;
    if (_isHost) {
      switch (message.type) {
        case 'hello':
          if (protocol.phase == 'ready') _send('state');
        case 'swap':
          if (protocol.phase != 'ready') return;
          if (message.revision == protocol.revision && !protocol.locked) {
            protocol.swap();
          }
          _send('state');
          _emit();
        case 'ack':
          if (protocol.phase == 'starting' &&
              message.revision == protocol.revision &&
              message.hostRole == protocol.hostRole &&
              _startAck?.isCompleted == false) {
            _startAck!.complete();
          }
        case 'closed':
          _fail(_error('O outro jogador saiu.'));
      }
    } else if (protocol.apply(message)) {
      if (message.type == 'prepare') {
        // Signaling is finished. Ignore its deletion after acknowledging start.
        unawaited(_stopSignaling());
        _send('ack');
        _startTimer?.cancel();
        _startTimer = Timer(const Duration(seconds: 15), () {
          if (protocol.phase == 'starting') {
            _fail(_error('O início do jogo não foi confirmado a tempo.'));
          }
        });
      }
      if (protocol.phase == 'playing') _startTimer?.cancel();
      _emit();
    }
  }

  Future<void> switchRoles(String roomId) async {
    _checkSession(roomId);
    if (_protocol!.locked) {
      throw _error('Os papéis estão fixos nesta sala.');
    }
    if (_isHost) {
      _protocol!.swap();
      if (_connected) _send('state');
      _emit();
    } else {
      if (_protocol!.phase != 'ready') {
        throw _error('A sala ainda não está pronta.');
      }
      _send('swap');
    }
  }

  Future<void> startGame(String roomId) async {
    _checkSession(roomId);
    if (!_isHost || !_connected || _guestUid == null) {
      throw _error('Os dois jogadores têm de estar ligados.');
    }
    _protocol!.prepare();
    _startAck = Completer<void>();
    _emit();
    try {
      _send('prepare');
      await _startAck!.future.timeout(const Duration(seconds: 10));
      await _stopSignaling();
      await _deleteMailbox();
      _send('start');
      _protocol!.phase = 'playing';
      _emit();
    } catch (_) {
      _protocol!.abortStart();
      if (_connected) _send('state');
      _emit();
      rethrow;
    } finally {
      _startAck = null;
    }
  }

  Future<void> _stopSignaling() async {
    _signalingClosed = true;
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _deleteMailbox() async {
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(_ref!);
      if (snapshot.data()?['session'] == _protocol!.session) tx.delete(_ref!);
    });
  }

  Future<void> deleteRoom(String roomId) async {
    _checkSession(roomId);
    if (!_isHost) throw _error('Só o anfitrião pode encerrar a sala.');
    await _deleteMailbox();
    await close();
  }

  Stream<Room?> watchRoom(String roomId) {
    _checkSession(roomId);
    return Stream<Room?>.multi((controller) {
      controller.add(_room);
      final subscription = _events.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  /// Gameplay transport over the reliable DataChannel retained after start.
  Stream<GameMessage> get gameMessages => _gameEvents.stream;

  Future<void> sendGameMessage({
    required String type,
    required int revision,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    if (!_connected || _protocol == null) {
      throw _error('Espera pela ligação ao outro jogador.');
    }
    final message = GameMessage(
      session: _protocol!.session,
      type: type,
      revision: revision,
      payload: payload,
    );
    await _channel!.send(RTCDataChannelMessage(message.encode()));
  }

  void _emit() {
    if (_disposed) return;
    _room = Room(
      id: _ref!.id,
      code: _ref!.id,
      hostUid: _hostUid!,
      guestUid: _guestUid,
      status: _protocol!.phase,
      expiresAt: _expiresAt!,
      rolesLocked: _protocol!.locked,
      hostRole: _protocol!.hostRole == 'manual'
          ? PlayerRole.manual
          : PlayerRole.defuser,
    );
    _events.add(_room);
  }

  void _fail(Object error) {
    if (_disposed || _protocol?.phase == 'closed') return;
    _protocol?.phase = 'closed';
    _connectionTimer?.cancel();
    _startTimer?.cancel();
    if (_startAck?.isCompleted == false) _startAck!.completeError(error);
    _emit();
    _events.addError(error);
  }

  void _validateRoomId(String code) {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw ArgumentError.value(code, 'code');
    }
  }

  void _checkSession(String roomId) {
    _validateRoomId(roomId);
    if (_disposed || _ref?.id != roomId) {
      throw _error('Não existe uma sala ativa.');
    }
  }

  /// Retain this service while playing; close it only when leaving the session.
  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    if (_connected) {
      try {
        await _channel!.send(
          RTCDataChannelMessage(_protocol!.message('closed').encode()),
        );
      } catch (_) {
        // A lost peer must not prevent local cleanup.
      }
    }
    _connectionTimer?.cancel();
    _startTimer?.cancel();
    await _stopSignaling();
    try {
      if (_isHost && _ref != null) await _deleteMailbox();
    } catch (_) {
      // Offline cleanup may fail; the code expires and can be removed later.
    }
    await _channel?.close();
    await _peer?.close();
    await _events.close();
    await _gameEvents.close();
  }
}
