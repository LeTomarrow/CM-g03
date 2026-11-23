import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:what_did_you_press/core/game_models.dart';
import 'package:what_did_you_press/services/anonymous_sign_in.dart';
import 'package:what_did_you_press/services/game_protocol.dart';
import 'package:what_did_you_press/services/game_transport.dart';
import 'package:what_did_you_press/services/room/peer_link.dart';
import 'package:what_did_you_press/services/room/room_models.dart';
import 'package:what_did_you_press/services/room/room_signaling.dart';
import 'package:what_did_you_press/services/room_protocol.dart';

export 'package:what_did_you_press/services/room/room_models.dart';

/// One lobby session. [RoomSignaling] finds the peer, [PeerLink] carries the
/// DataChannel and [RoomProtocol] decides roles and start. Firestore is only a
/// rendezvous mailbox; the host serializes every role/start decision.
class RoomService implements GameTransport {
  RoomService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _signaling = RoomSignaling(firestore ?? FirebaseFirestore.instance);

  final FirebaseAuth _auth;
  final RoomSignaling _signaling;
  final _events = StreamController<Room?>.broadcast();
  final _gameEvents = StreamController<GameMessage>.broadcast();
  RoomMailbox? _mailbox;
  StreamSubscription<Map<String, dynamic>?>? _subscription;
  PeerLink? _link;
  RoomProtocol? _protocol;
  String? _hostUid;
  String? _guestUid;
  DateTime? _expiresAt;
  Room? _room;
  Future<void> _signalQueue = Future.value();
  bool _remoteDescriptionSet = false;
  bool _signalingClosed = false;
  bool _disposed = false;
  Timer? _connectionTimer;
  Timer? _startTimer;
  Completer<void>? _startAck;

  // ICE restart during a game (see [_onLinkDown]).
  static const _reconnectWindow = Duration(seconds: 30);
  static const _attemptTimeout = Duration(seconds: 8);
  final _linkStatus = StreamController<bool>.broadcast();
  ReconnectMailbox? _reconnect;
  StreamSubscription<Map<String, dynamic>?>? _reconnectSubscription;
  Future<void> _reconnectQueue = Future.value();
  int _attempt = 0;
  bool _attemptRemoteSet = false;
  bool _linkDown = false;
  Timer? _reconnectDeadline;
  Timer? _attemptTimer;

  /// Keeps the host's role fixed, e.g. the operator of an open-world bomb.
  /// Guest swap requests are answered with the unchanged state.
  bool rolesLocked = false;

  String? get currentUserId => _auth.currentUser?.uid;
  bool get _isHost => _hostUid == currentUserId;
  bool get _connected => _link?.isOpen ?? false;

  void _requireNewSession() {
    if (_mailbox != null || _disposed) {
      throw roomError('Sai da sala atual antes de criar outra.');
    }
  }

  Future<RoomConnection> createRoom() async {
    _requireNewSession();
    await ensureSignedIn(_auth);
    final uid = currentUserId!;
    final random = Random.secure();
    for (var attempt = 0; attempt < 10; attempt++) {
      final code = (100000 + random.nextInt(900000)).toString();
      final session = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final expiry = DateTime.now().add(const Duration(hours: 1));
      final mailbox = await _signaling.reserve(
        code: code,
        session: session,
        hostUid: uid,
        expiresAt: expiry,
      );
      if (mailbox == null) continue;
      await _begin(mailbox, session, uid, null, expiry);
      return RoomConnection(roomId: code, code: code);
    }
    throw roomError('Não foi possível reservar um código. Tenta novamente.');
  }

  Future<RoomConnection> joinRoom(String code) async {
    _requireNewSession();
    code = code.trim();
    _validateRoomId(code);
    await ensureSignedIn(_auth);
    final uid = currentUserId!;
    final joined = await _signaling.join(code, uid);
    await _begin(
      joined.mailbox,
      joined.session,
      joined.hostUid,
      uid,
      joined.expiresAt,
    );
    return RoomConnection(roomId: code, code: code);
  }

  Future<void> _begin(
    RoomMailbox mailbox,
    String session,
    String host,
    String? guest,
    DateTime expiry,
  ) async {
    _mailbox = mailbox;
    _hostUid = host;
    _guestUid = guest;
    _expiresAt = expiry;
    _protocol = RoomProtocol(session: session, isHost: _isHost)
      ..locked = _isHost && rolesLocked;
    _emit();
    try {
      final link = _link = await PeerLink.connect(
        onLocalCandidate: (candidate) {
          if (_attempt > 0) {
            _sendReconnectCandidate(candidate);
            return;
          }
          if (_signalingClosed) return;
          unawaited(
            mailbox.addCandidate(candidate, fromHost: _isHost).catchError((
              Object error,
            ) {
              if (!_signalingClosed) _fail(error);
            }),
          );
        },
        onText: _onText,
        onOpen: _onChannelOpen,
        onClosed: () {
          if (_disposed || _protocol?.phase == 'closed') return;
          _fail(roomError('O outro jogador desligou-se.'));
        },
        onFailed: () {
          // In a game the reconnect window decides; elsewhere it is final.
          if (_protocol?.phase == 'playing') return;
          _fail(
            roomError('A ligação entre jogadores falhou. Cria uma nova sala.'),
          );
        },
        onDisconnected: _onLinkDown,
        onReconnected: _onLinkUp,
      );
      if (_isHost) {
        await link.openChannel();
        await mailbox.writeOffer(await link.createOffer());
      }
      _subscription = mailbox.watch().listen(
        (data) {
          _signalQueue = _signalQueue
              .then((_) => _readSignaling(data))
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

  Future<void> _readSignaling(Map<String, dynamic>? data) async {
    if (_disposed || _signalingClosed) return;
    if (data == null || data['session'] != _protocol!.session) {
      _fail(roomError('O anfitrião encerrou a sala.'));
      return;
    }
    _guestUid = data['guestUid'] as String?;
    _armConnectionTimeout();
    _emit();
    final link = _link!;
    final description = data[_isHost ? 'answer' : 'offer'];
    if (!_remoteDescriptionSet && description is Map) {
      await link.setRemoteDescription(description);
      _remoteDescriptionSet = true;
      if (!_isHost) {
        final answer = await link.createAnswer();
        if (!_signalingClosed) await _mailbox!.writeAnswer(answer);
      }
    }
    if (!_remoteDescriptionSet) return;
    await link.addRemoteCandidates(
      data[_isHost ? 'guestCandidates' : 'hostCandidates'] as List,
    );
  }

  void _armConnectionTimeout() {
    if (_guestUid == null || _connected) return;
    _connectionTimer ??= Timer(const Duration(seconds: 60), () {
      if (!_connected) {
        _fail(roomError('A ligação demorou demasiado. Cria uma nova sala.'));
      }
    });
  }

  void _onChannelOpen() {
    if (_disposed || _protocol?.phase == 'closed') return;
    _connectionTimer?.cancel();
    _protocol!.connected();
    _emit();
    _send(_isHost ? 'state' : 'hello');
  }

  /// Lobby messages first; anything else on the channel must be a game message.
  void _onText(String text) {
    if (_disposed) return;
    try {
      try {
        _receive(RoomMessage.decode(text, _protocol!.session));
      } on FormatException {
        _gameEvents.add(GameMessage.decode(text, _protocol!.session));
      }
    } on FormatException {
      // Ignore malformed or unrelated packets; never infer identity from JSON.
    } catch (error) {
      _fail(error);
    }
  }

  void _send(String type) {
    if (!_connected) throw roomError('Espera pela ligação ao outro jogador.');
    unawaited(
      _link!
          .send(_protocol!.message(type).encode())
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
          _gameEvents.add(
            GameMessage(
              session: protocol.session,
              type: 'ended',
              revision: protocol.revision,
              payload: {'reason': 'opponent_left'},
            ),
          );
          _fail(roomError('O outro jogador saiu.'));
      }
    } else if (protocol.apply(message)) {
      if (message.type == 'prepare') {
        // Signaling is finished. Ignore its deletion after acknowledging start.
        unawaited(_stopSignaling());
        _send('ack');
        _startTimer?.cancel();
        _startTimer = Timer(const Duration(seconds: 15), () {
          if (protocol.phase == 'starting') {
            _fail(roomError('O início do jogo não foi confirmado a tempo.'));
          }
        });
      }
      if (protocol.phase == 'playing') {
        _startTimer?.cancel();
        _watchReconnects();
      }
      _emit();
    }
  }

  Future<void> switchRoles(String roomId) async {
    _checkSession(roomId);
    if (_protocol!.locked) {
      throw roomError('Os papéis estão fixos nesta sala.');
    }
    if (_isHost) {
      _protocol!.swap();
      if (_connected) _send('state');
      _emit();
    } else {
      if (_protocol!.phase != 'ready') {
        throw roomError('A sala ainda não está pronta.');
      }
      _send('swap');
    }
  }

  Future<void> startGame(String roomId) async {
    _checkSession(roomId);
    if (!_isHost || !_connected || _guestUid == null) {
      throw roomError('Os dois jogadores têm de estar ligados.');
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
      _watchReconnects();
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

  Future<void> _deleteMailbox() =>
      _mailbox!.deleteIfSession(_protocol!.session);

  Future<void> deleteRoom(String roomId) async {
    _checkSession(roomId);
    if (!_isHost) throw roomError('Só o anfitrião pode encerrar a sala.');
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
  @override
  Stream<GameMessage> get gameMessages => _gameEvents.stream;

  @override
  Stream<bool> get linkStatus => _linkStatus.stream;

  // ── Reconnection ──────────────────────────────────────────────────────────
  //
  // The DataChannel survives an ICE restart, so a network change (Wi-Fi ↔
  // mobile data, a short outage, the app resuming from background) is healed
  // on the same connection and the game messages queued meanwhile still
  // arrive. The host, as the original offerer, publishes each new offer in
  // `reconnects/{session}`; the guest watches it for the whole game.

  void _watchReconnects() {
    if (_reconnect != null || _disposed) return;
    final mailbox = _reconnect = _signaling.reconnect(_protocol!.session);
    _reconnectSubscription = mailbox.watch().listen(
      (data) {
        _reconnectQueue = _reconnectQueue
            .then((_) => _readReconnect(data))
            .catchError((Object _) {
              // A broken attempt is retried until the window closes.
            });
      },
      onError: (Object _) {
        // Offline listeners resume by themselves; the window decides.
      },
    );
  }

  void _onLinkDown() {
    if (_disposed || _linkDown || _protocol?.phase != 'playing') return;
    _linkDown = true;
    _linkStatus.add(false);
    _reconnectDeadline = Timer(_reconnectWindow, () {
      if (_linkDown) _fail(roomError('Não foi possível voltar a ligar.'));
    });
    if (_isHost) _restartIce();
  }

  void _onLinkUp() {
    if (_disposed || !_linkDown) return;
    _linkDown = false;
    _reconnectDeadline?.cancel();
    _attemptTimer?.cancel();
    _linkStatus.add(true);
  }

  /// Host only: one attempt, retried while the link stays down.
  void _restartIce() {
    _reconnectQueue = _reconnectQueue
        .then((_) async {
          if (_disposed || !_linkDown) return;
          final mailbox = _reconnect;
          final guest = _guestUid;
          if (mailbox == null || guest == null) return;
          _attempt++;
          _attemptRemoteSet = false;
          final offer = await _link!.createRestartOffer();
          // Not awaited: offline, Firestore queues the write until it can send.
          unawaited(
            mailbox
                .writeAttempt(
                  attempt: _attempt,
                  hostUid: _hostUid!,
                  guestUid: guest,
                  offer: offer,
                )
                .catchError((Object _) {}),
          );
          _attemptTimer?.cancel();
          _attemptTimer = Timer(_attemptTimeout, () {
            if (_linkDown) _restartIce();
          });
        })
        .catchError((Object _) {});
  }

  Future<void> _readReconnect(Map<String, dynamic>? data) async {
    if (_disposed || data == null) return;
    final link = _link!;
    final attempt = data['attempt'];
    if (attempt is! int) return;
    if (_isHost) {
      if (attempt != _attempt) return;
      final answer = data['answer'];
      if (!_attemptRemoteSet && answer is Map) {
        await link.setRemoteDescription(answer);
        _attemptRemoteSet = true;
      }
      if (_attemptRemoteSet) {
        await link.addRemoteCandidates(
          data['guestCandidates'] as List,
          tolerant: true,
        );
      }
      return;
    }
    // Guest: answer every new attempt, even if this side never saw the drop.
    final offer = data['offer'];
    if (attempt > _attempt && offer is Map) {
      _attempt = attempt;
      _attemptRemoteSet = false;
      await link.setRemoteDescription(offer);
      _attemptRemoteSet = true;
      final answer = await link.createAnswer();
      unawaited(_reconnect!.writeAnswer(answer).catchError((Object _) {}));
    }
    if (attempt == _attempt && _attemptRemoteSet) {
      await link.addRemoteCandidates(
        data['hostCandidates'] as List,
        tolerant: true,
      );
    }
  }

  void _sendReconnectCandidate(Object? candidate) {
    final mailbox = _reconnect;
    if (mailbox == null || _disposed) return;
    unawaited(
      mailbox
          .addCandidate(candidate, fromHost: _isHost)
          .catchError((Object _) {}),
    );
  }

  @override
  Future<void> sendGameMessage({
    required String type,
    required int revision,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    if (!_connected || _protocol == null) {
      throw roomError('Espera pela ligação ao outro jogador.');
    }
    final message = GameMessage(
      session: _protocol!.session,
      type: type,
      revision: revision,
      payload: payload,
    );
    await _link!.send(message.encode());
  }

  void _emit() {
    if (_disposed) return;
    _room = Room(
      id: _mailbox!.code,
      code: _mailbox!.code,
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
    if (_protocol?.phase == 'playing') {
      _gameEvents.add(
        GameMessage(
          session: _protocol!.session,
          type: 'ended',
          revision: _protocol!.revision,
          payload: {'reason': 'connection_lost'},
        ),
      );
    }
    _protocol?.phase = 'closed';
    _connectionTimer?.cancel();
    _startTimer?.cancel();
    _reconnectDeadline?.cancel();
    _attemptTimer?.cancel();
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
    if (_disposed || _mailbox?.code != roomId) {
      throw roomError('Não existe uma sala ativa.');
    }
  }

  /// Retain this service while playing; close it only when leaving the session.
  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    if (_connected) {
      try {
        await _link!.send(_protocol!.message('closed').encode());
      } catch (_) {
        // A lost peer must not prevent local cleanup.
      }
    }
    _connectionTimer?.cancel();
    _startTimer?.cancel();
    _reconnectDeadline?.cancel();
    _attemptTimer?.cancel();
    await _stopSignaling();
    await _reconnectSubscription?.cancel();
    try {
      if (_isHost && _mailbox != null) await _deleteMailbox();
    } catch (_) {
      // Offline cleanup may fail; the code expires and can be removed later.
    }
    if (_reconnect != null) {
      // Either player may clean up; the document may already be gone.
      unawaited(_reconnect!.delete().catchError((Object _) {}));
    }
    await _link?.close();
    await _events.close();
    await _gameEvents.close();
    await _linkStatus.close();
  }
}
