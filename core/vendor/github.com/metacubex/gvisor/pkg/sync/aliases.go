// Copyright 2020 The gVisor Authors.
//
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package sync

import (
	"github.com/metacubex/gvisor/pkg/common"
	"sync"
)

// Aliases of standard library types.
type (
	// Cond is an alias of sync.Cond.
	Cond = sync.Cond

	// Locker is an alias of sync.Locker.
	Locker = sync.Locker

	// Once is an alias of sync.Once.
	Once = sync.Once

	// Pool is an alias of sync.Pool.
	Pool = sync.Pool

	// WaitGroup is an alias of sync.WaitGroup.
	WaitGroup = sync.WaitGroup

	// Map is an alias of sync.Map.
	Map = sync.Map
)

// NewCond is a wrapper around sync.NewCond.
func NewCond(l Locker) *Cond {
	return sync.NewCond(l)
}

// OnceFunc is a wrapper around sync.OnceFunc.
func OnceFunc(f func()) func() {
	return common.OnceFunc(f)
}

// OnceValue is a wrapper around sync.OnceValue.
func OnceValue[T any](f func() T) func() T {
	return common.OnceValue(f)
}

// OnceValues is a wrapper around sync.OnceValues.
func OnceValues[T1, T2 any](f func() (T1, T2)) func() (T1, T2) {
	return common.OnceValues(f)
}
