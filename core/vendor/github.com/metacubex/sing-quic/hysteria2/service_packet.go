package hysteria2

import (
	"github.com/metacubex/sing/common"
	"github.com/metacubex/sing/common/auth"
	"github.com/metacubex/sing/common/canceler"
	E "github.com/metacubex/sing/common/exceptions"
	M "github.com/metacubex/sing/common/metadata"
)

func (s *serverSession[U]) loopMessages() {
	for {
		message, err := s.quicConn.ReceiveDatagram(s.ctx)
		if err != nil {
			s.closeWithError(E.Cause(err, "receive message"))
			return
		}
		hErr := s.handleMessage(message)
		if hErr != nil {
			s.closeWithError(E.Cause(hErr, "handle message"))
			return
		}
	}
}

func (s *serverSession[U]) handleMessage(data []byte) error {
	message := allocMessage()
	err := decodeUDPMessage(message, data)
	if err != nil {
		message.release()
		return E.Cause(err, "decode UDP message")
	}
	s.handleUDPMessage(message)
	return nil
}

func (s *serverSession[U]) handleUDPMessage(message *udpMessage) {
	s.udpAccess.RLock()
	udpConn, loaded := s.udpConnMap[message.sessionID]
	s.udpAccess.RUnlock()
	if !loaded || common.Done(udpConn.ctx) {
		udpConn = newUDPPacketConn(auth.ContextWithUser(s.ctx, s.authUser), s.quicConn, func() {
			s.udpAccess.Lock()
			delete(s.udpConnMap, message.sessionID)
			s.udpAccess.Unlock()
		}, s.udpMTU)
		udpConn.sessionID = message.sessionID
		s.udpAccess.Lock()
		s.udpConnMap[message.sessionID] = udpConn
		s.udpAccess.Unlock()
		newCtx, newConn := canceler.NewPacketConn(udpConn.ctx, udpConn, s.udpTimeout)
		go s.handler.NewPacketConnection(newCtx, newConn, M.Metadata{
			Source:      M.SocksaddrFromNet(s.quicConn.RemoteAddr()),
			Destination: M.ParseSocksaddr(message.destination),
		})
	}
	udpConn.inputPacket(message)
}
