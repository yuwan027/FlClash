package vless

import (
	"net"
	"reflect"
	"unsafe"
)

func RegisterTLS(fn func(conn net.Conn) (loaded bool, netConn net.Conn, reflectType reflect.Type, reflectPointer unsafe.Pointer)) {
	tlsRegistry = append(tlsRegistry, fn)
}
