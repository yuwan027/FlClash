package shadowtls

import (
	"context"
	"net"
)

type (
	TLSSessionIDGeneratorFunc func(clientHello []byte, sessionID []byte) error

	TLSHandshakeFunc func(
		ctx context.Context,
		conn net.Conn,
		sessionIDGenerator TLSSessionIDGeneratorFunc, // for shadow-tls version 3
	) error
)
