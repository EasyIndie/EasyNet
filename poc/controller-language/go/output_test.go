package sshlab

import (
	"bytes"
	"errors"
	"sync"
	"testing"
)

func TestBoundedOutputBoundaries(t *testing.T) {
	cases := []struct {
		name     string
		chunks   []int
		counts   []int
		overflow []bool
	}{
		{"zero", []int{0}, []int{0}, []bool{false}},
		{"exact", []int{4096, 0}, []int{4096, 0}, []bool{false, false}},
		{"excess", []int{4097, 1, 0}, []int{4096, 0, 0}, []bool{true, true, true}},
		{"straddle", []int{4090, 10, 1}, []int{4090, 6, 0}, []bool{false, true, true}},
	}
	for _, example := range cases {
		t.Run(example.name, func(t *testing.T) {
			output := new(boundedOutput)
			retained := 0
			for index, size := range example.chunks {
				data := bytes.Repeat([]byte("x"), size)
				count, err := output.Write(data)
				if count != example.counts[index] || example.overflow[index] != errors.Is(err, ErrOutputLimit) || !example.overflow[index] && err != nil {
					t.Fatalf("write %d: count=%d err=%v", index, count, err)
				}
				if output.Overflowed() != example.overflow[index] {
					t.Fatal("overflow snapshot mismatch")
				}
				retained += count
				for i := range data {
					data[i] = 'z'
				}
				snapshot := output.Bytes()
				if len(snapshot) != retained || retained > outputLimit || !bytes.Equal(snapshot, bytes.Repeat([]byte("x"), retained)) {
					t.Fatalf("retained output after write %d: length %d", index, len(snapshot))
				}
				if len(snapshot) > 0 {
					snapshot[0] = 'z'
				}
				if !bytes.Equal(output.Bytes(), bytes.Repeat([]byte("x"), retained)) {
					t.Fatal("snapshot overwrote output")
				}
			}
		})
	}
}
func TestBoundedOutputConcurrentStreams(t *testing.T) {
	output := new(boundedOutput)
	var streams sync.WaitGroup
	ready := make(chan struct{})
	finished := make(chan struct{})
	readerDone := make(chan struct{})
	go func() {
		defer close(readerDone)
		close(ready)
		for {
			snapshot := output.Bytes()
			if len(snapshot) > outputLimit {
				t.Errorf("oversize snapshot: %d", len(snapshot))
			}
			if len(snapshot) > 0 {
				snapshot[0] = 'z'
			}
			select {
			case <-finished:
				return
			default:
			}
		}
	}()
	<-ready
	counts := make(chan int, 2)
	for _, stream := range []byte{'o', 'e'} {
		streams.Add(1)
		go func(marker byte) {
			defer streams.Done()
			count := 0
			for range 24 {
				n, err := output.Write(bytes.Repeat([]byte{marker}, 128))
				if n < 0 || n > 128 || err != nil && !errors.Is(err, ErrOutputLimit) || err == nil && n != 128 {
					t.Errorf("stream write n=%d err=%v", n, err)
				}
				count += n
			}
			counts <- count
		}(stream)
	}
	streams.Wait()
	close(finished)
	<-readerDone
	first, second := <-counts, <-counts
	snapshot := output.Bytes()
	if first+second != outputLimit || len(snapshot) != outputLimit || first < 1024 || second < 1024 {
		t.Fatalf("stream retention: %d + %d, bytes %d", first, second, len(snapshot))
	}
	if bytes.Count(snapshot, []byte("o"))+bytes.Count(snapshot, []byte("e")) != outputLimit {
		t.Fatal("concurrent snapshot overwritten")
	}
	if n, err := output.Write([]byte("extra")); n != 0 || !errors.Is(err, ErrOutputLimit) {
		t.Fatalf("persistent overflow: n=%d err=%v", n, err)
	}
}
