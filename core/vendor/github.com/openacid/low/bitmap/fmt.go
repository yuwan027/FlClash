package bitmap

import (
	"fmt"
	"math/bits"
	"reflect"
	"strings"
)

// Fmt converts bitmap in an integer or in a slice of integer to binary format string,
// with significant bits at right.
// E.g.:
//    int32(0x0102) --> 01000000 10000000
//
// Since 0.1.11
func Fmt(x interface{}) string {

	rst := []string{}

	v := reflect.ValueOf(x)
	if v.Kind() == reflect.Slice {
		n := v.Len()
		for i := 0; i < n; i++ {
			rst = append(rst, intFmt(v.Index(i).Interface()))
		}
		return strings.Join(rst, ",")

	} else {
		return intFmt(x)
	}
}

func intFmt(i interface{}) string {

	sz, v := intSize(i)

	rst := []string{}
	for i := 0; i < sz; i++ {
		b := uint8(v >> uint(i*8))
		s := fmt.Sprintf("%08b", bits.Reverse8(b))
		rst = append(rst, s)
	}
	return strings.Join(rst, " ")
}

func intSize(i interface{}) (int, uint64) {
	switch i := i.(type) {
	case int8:
		return 1, uint64(i)
	case uint8:
		return 1, uint64(i)
	case int16:
		return 2, uint64(i)
	case uint16:
		return 2, uint64(i)
	case int32:
		return 4, uint64(i)
	case uint32:
		return 4, uint64(i)
	case int64:
		return 8, uint64(i)
	case uint64:
		return 8, i
	}

	panic(fmt.Sprintf("not a int type: %v", i))
}
