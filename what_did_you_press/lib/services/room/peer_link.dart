import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// One WebRTC peer with the reliable, ordered DataChannel `room-v1`.
/// Knows nothing about Firestore or the lobby protocol; it only moves text.
class PeerLink {
  PeerLink._(this._peer, this._onText, this._onOpen, this._onClosed);

  static const _label = 'room-v1';

  // For arbitrary networks configure a TURN relay; STUN alone is best effort.
  static const _stun = String.fromEnvironment(
    'WEBRTC_STUN_URL',
    defaultValue: 'stun:stun.l.google.com:19302',
  );
  static const _turn = String.fromEnvironment('WEBRTC_TURN_URL');
  static const _turnUsername = String.fromEnvironment('WEBRTC_TURN_USERNAME');
  static const _turnCredential = String.fromEnvironment(
    'WEBRTC_TURN_CREDENTIAL',
  );

  final RTCPeerConnection _peer;
  final void Function(String text) _onText;
  final void Function() _onOpen;
  final void Function() _onClosed;
  final Set<String> _remoteCandidates = {};
  RTCDataChannel? _channel;

  static Future<PeerLink> connect({
    required void Function(Object? candidate) onLocalCandidate,
    required void Function(String text) onText,
    required void Function() onOpen,
    required void Function() onClosed,
    required void Function() onFailed,
    void Function()? onDisconnected,
    void Function()? onReconnected,
  }) async {
    final peer = await createPeerConnection({
      'iceServers': [
        {'urls': _stun},
        if (_turn.isNotEmpty)
          {
            'urls': _turn,
            'username': _turnUsername,
            'credential': _turnCredential,
          },
      ],
    });
    final link = PeerLink._(peer, onText, onOpen, onClosed);
    peer.onIceCandidate = (candidate) {
      if (candidate.candidate?.isNotEmpty != true) return;
      onLocalCandidate(candidate.toMap());
    };
    peer.onDataChannel = link._attach;
    // ICE can drop and recover while the DataChannel (SCTP) stays open, so
    // the room service may restart ICE instead of tearing the session down.
    peer.onConnectionState = (state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          onReconnected?.call();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          onDisconnected?.call();
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          onDisconnected?.call();
          onFailed();
        default:
      }
    };
    return link;
  }

  bool get isOpen => _channel?.state == RTCDataChannelState.RTCDataChannelOpen;

  /// Host side: the offerer creates the channel before the offer.
  Future<void> openChannel() async {
    _attach(
      await _peer.createDataChannel(
        _label,
        RTCDataChannelInit()..ordered = true,
      ),
    );
  }

  Future<Object?> createOffer() async {
    final offer = await _peer.createOffer();
    await _peer.setLocalDescription(offer);
    return offer.toMap();
  }

  /// Offerer side: new ICE credentials on the same connection and channel.
  Future<Object?> createRestartOffer() async {
    await _peer.restartIce();
    return createOffer();
  }

  Future<Object?> createAnswer() async {
    final answer = await _peer.createAnswer();
    await _peer.setLocalDescription(answer);
    return answer.toMap();
  }

  Future<void> setRemoteDescription(Map<dynamic, dynamic> description) =>
      _peer.setRemoteDescription(
        RTCSessionDescription(
          description['sdp'] as String,
          description['type'] as String,
        ),
      );

  /// Adds each candidate once; signaling resends the whole list every time.
  ///
  /// With [tolerant], a rejected candidate is skipped: after an ICE restart a
  /// late candidate may still carry the previous credentials.
  Future<void> addRemoteCandidates(
    List<dynamic> candidates, {
    bool tolerant = false,
  }) async {
    for (final candidate in candidates) {
      if (!_remoteCandidates.add(jsonEncode(candidate))) continue;
      final future = _peer.addCandidate(
        RTCIceCandidate(
          candidate['candidate'] as String?,
          candidate['sdpMid'] as String?,
          candidate['sdpMLineIndex'] as int?,
        ),
      );
      if (!tolerant) {
        await future;
        continue;
      }
      try {
        await future;
      } catch (_) {
        // Stale candidate from an older ICE generation.
      }
    }
  }

  Future<void> send(String text) => _channel!.send(RTCDataChannelMessage(text));

  Future<void> close() async {
    await _channel?.close();
    await _peer.close();
  }

  void _attach(RTCDataChannel channel) {
    if (channel.label != _label) return;
    _channel = channel;
    channel.onMessage = (message) {
      if (!message.isBinary) _onText(message.text);
    };
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _onOpen();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _onClosed();
      }
    };
    // Native peers can deliver an already-open channel in onDataChannel.
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) _onOpen();
  }
}
