package hkdf

import (
	"crypto/hmac"
	"hash"
)

func Extract(h func() hash.Hash, secret, salt []byte) []byte {
	if salt == nil {
		salt = make([]byte, h().Size())
	}
	extractor := hmac.New(h, salt)
	extractor.Write(secret)

	return extractor.Sum(nil)
}

func Expand(h func() hash.Hash, pseudorandomKey []byte, info string, keyLen int) []byte {
	out := make([]byte, 0, keyLen)
	expander := hmac.New(h, pseudorandomKey)
	var counter uint8
	var buf []byte

	for len(out) < keyLen {
		counter++
		if counter == 0 {
			panic("hkdf: counter overflow")
		}
		if counter > 1 {
			expander.Reset()
		}
		expander.Write(buf)
		expander.Write([]byte(info))
		expander.Write([]byte{counter})
		buf = expander.Sum(buf[:0])
		remain := keyLen - len(out)
		if len(buf) < remain {
			remain = len(buf)
		}
		out = append(out, buf[:remain]...)
	}

	return out
}
