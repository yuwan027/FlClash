package shadowimpl

import (
	"time"

	"github.com/metacubex/sing-shadowsocks"
	"github.com/metacubex/sing-shadowsocks/shadowaead"
	"github.com/metacubex/sing-shadowsocks/shadowaead_2022"
	"github.com/metacubex/sing-shadowsocks/shadowstream"
	"github.com/metacubex/sing/common"
	E "github.com/metacubex/sing/common/exceptions"
)

func FetchMethod(method string, password string, timeFunc func() time.Time) (shadowsocks.Method, error) {
	if method == "none" || method == "plain" || method == "dummy" {
		return shadowsocks.NewNone(), nil
	} else if common.Contains(shadowstream.List, method) {
		return shadowstream.New(method, nil, password)
	} else if common.Contains(shadowaead.List, method) {
		return shadowaead.New(method, nil, password)
	} else if common.Contains(shadowaead_2022.List, method) {
		return shadowaead_2022.NewWithPassword(method, password, timeFunc)
	} else {
		return nil, E.New("shadowsocks: unsupported method ", method)
	}
}
