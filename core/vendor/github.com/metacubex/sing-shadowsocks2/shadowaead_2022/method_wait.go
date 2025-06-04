package shadowaead_2022

import (
	"github.com/metacubex/sing/common/buf"
	"github.com/metacubex/sing/common/bufio"
	M "github.com/metacubex/sing/common/metadata"
	N "github.com/metacubex/sing/common/network"
)

var _ N.ReadWaiter = (*clientConn)(nil)

func (c *clientConn) InitializeReadWaiter(options N.ReadWaitOptions) (needCopy bool) {
	if c.reader == nil {
		c.readWaitOptions = options
		return options.NeedHeadroom()
	}
	return c.reader.InitializeReadWaiter(options)
}

func (c *clientConn) WaitReadBuffer() (buffer *buf.Buffer, err error) {
	if c.reader == nil {
		err = c.readResponse()
		if err != nil {
			return
		}
	}
	return c.reader.WaitReadBuffer()
}

var _ N.PacketReadWaitCreator = (*clientPacketConn)(nil)

func (c *clientPacketConn) CreateReadWaiter() (N.PacketReadWaiter, bool) {
	readWaiter, isReadWaiter := bufio.CreateReadWaiter(c.reader)
	if !isReadWaiter {
		return nil, false
	}
	return &clientPacketReadWaiter{c, readWaiter}, true
}

var _ N.PacketReadWaiter = (*clientPacketReadWaiter)(nil)

type clientPacketReadWaiter struct {
	*clientPacketConn
	readWaiter N.ReadWaiter
}

func (w *clientPacketReadWaiter) InitializeReadWaiter(options N.ReadWaitOptions) (needCopy bool) {
	return w.readWaiter.InitializeReadWaiter(options)
}

func (w *clientPacketReadWaiter) WaitReadPacket() (buffer *buf.Buffer, destination M.Socksaddr, err error) {
	buffer, err = w.readWaiter.WaitReadBuffer()
	if err != nil {
		return
	}
	destination, err = w.readPacket(buffer)
	if err != nil {
		buffer.Release()
		return nil, M.Socksaddr{}, err
	}
	return
}
