//go:build freebsd || linux || windows

package tfo

import (
	"context"
	"errors"
	"net"
	"syscall"
)

// defaultBacklog is Go std's listen(2) backlog.
// We use this as the default TFO backlog.
const defaultBacklog = 4096

func (lc *ListenConfig) listenTFO(ctx context.Context, network, address string) (net.Listener, error) {
	ctrlFn := lc.Control
	backlog := lc.Backlog
	if backlog == 0 {
		backlog = defaultBacklog
	}
	llc := *lc
	llc.Control = func(network, address string, c syscall.RawConn) (err error) {
		if ctrlFn != nil {
			if err = ctrlFn(network, address, c); err != nil {
				return err
			}
		}

		if cerr := c.Control(func(fd uintptr) {
			err = setTFOListenerWithBacklog(fd, backlog)
		}); cerr != nil {
			return cerr
		}

		if err != nil {
			if !lc.Fallback || !errors.Is(err, ErrUnsupported) {
				return wrapSyscallError("setsockopt(TCP_FASTOPEN)", err)
			}
			runtimeListenNoTFO.Store(true)
		}
		return nil
	}
	return llc.ListenConfig.Listen(ctx, network, address)
}
