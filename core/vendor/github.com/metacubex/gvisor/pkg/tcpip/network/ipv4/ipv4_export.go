package ipv4

import (
	"github.com/metacubex/gvisor/pkg/tcpip"
	"github.com/metacubex/gvisor/pkg/tcpip/stack"
)

type ExportedEndpoint interface {
	WritePacketDirect(r *stack.Route, pkt *stack.PacketBuffer) tcpip.Error
}

func (e *endpoint) WritePacketDirect(r *stack.Route, pkt *stack.PacketBuffer) tcpip.Error {
	return e.writePacket(r, pkt)
}
