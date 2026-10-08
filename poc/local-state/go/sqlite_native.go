//go:build darwin && cgo

package statelab

/*
#cgo LDFLAGS: -lsqlite3
#include <sqlite3.h>
#include <stdlib.h>
static int configure(sqlite3 *db, int *stage, int *code, int *actual) {
 int opts[] = {SQLITE_DBCONFIG_DEFENSIVE, SQLITE_DBCONFIG_TRUSTED_SCHEMA,
               SQLITE_DBCONFIG_DQS_DDL, SQLITE_DBCONFIG_DQS_DML,
               SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION};
 for (int i=0; i<5; i++) {
  int wanted = i==0 ? 1 : 0;
  *stage=i+1; *actual=-1;
  if (i==4 && sqlite3_compileoption_used("OMIT_LOAD_EXTENSION")==1) {
   *code=SQLITE_OK; *actual=0;
   continue; // Linked library has no extension-loading mechanism.
  }
  *code = sqlite3_db_config(db, opts[i], wanted, actual);
  if (*code != SQLITE_OK || *actual != wanted) return SQLITE_ERROR;
 }
 sqlite3_limit(db, SQLITE_LIMIT_SQL_LENGTH, 4096);
 sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 32768);
 sqlite3_limit(db, SQLITE_LIMIT_ATTACHED, 0);
 int limits[] = {SQLITE_LIMIT_SQL_LENGTH, SQLITE_LIMIT_LENGTH, SQLITE_LIMIT_ATTACHED};
 int expected[] = {4096,32768,0};
 for (int i=0;i<3;i++) {
  *stage=i+6; *code=SQLITE_OK; *actual=sqlite3_limit(db,limits[i],-1);
  if (*actual!=expected[i]) return SQLITE_ERROR;
 }
 *stage=9; *actual=0; *code=sqlite3_busy_timeout(db,1000);
 return *code;
}
static int bind_bytes(sqlite3_stmt *s, int i, const void *p, int n) {
 return sqlite3_bind_blob(s, i, p, n, SQLITE_TRANSIENT);
}
*/
import "C"

import "unsafe"

type sqliteDB struct{ ptr *C.sqlite3 }
type sqliteStmt struct{ ptr *C.sqlite3_stmt }
type sqliteValue struct {
	kind   int
	number int64
	bytes  []byte
}

const (
	sqlInteger = 1
	sqlText    = 3
	sqlBlob    = 4
	sqlNull    = 5
)

func sqliteError(rc C.int) error {
	switch int(rc) & 255 {
	case int(C.SQLITE_OK):
		return nil
	case int(C.SQLITE_CORRUPT), int(C.SQLITE_NOTADB):
		return ErrCorrupt
	case int(C.SQLITE_CONSTRAINT), int(C.SQLITE_MISMATCH):
		return ErrInvalid
	default:
		return ErrIO
	}
}
func openSQLite(path string, readonly bool) (*sqliteDB, error) {
	return openSQLiteWithProbe(path, readonly, nil)
}
func openSQLiteWithProbe(path string, readonly bool, probe func(int, int, int)) (*sqliteDB, error) {
	name := C.CString(path)
	defer C.free(unsafe.Pointer(name))
	flags := C.int(C.SQLITE_OPEN_READWRITE | C.SQLITE_OPEN_NOFOLLOW)
	if readonly {
		flags = C.SQLITE_OPEN_READONLY | C.SQLITE_OPEN_NOFOLLOW
	}
	d := &sqliteDB{}
	rc := C.sqlite3_open_v2(name, &d.ptr, flags, nil)
	if e := sqliteError(rc); e != nil {
		if d.ptr != nil {
			if d.close() != nil {
				return nil, ErrIO
			}
		}
		return nil, e
	}
	var stage, code, actual C.int
	configured := C.configure(d.ptr, &stage, &code, &actual)
	if probe != nil {
		probe(int(stage), int(code), int(actual))
	}
	if sqliteError(configured) != nil {
		d.close()
		return nil, ErrIO
	}
	main := C.CString("main")
	mode := C.sqlite3_db_readonly(d.ptr, main)
	C.free(unsafe.Pointer(main))
	want := C.int(0)
	if readonly {
		want = 1
	}
	if mode != want {
		d.close()
		return nil, ErrIO
	}
	return d, nil
}
func (d *sqliteDB) close() error {
	if d.ptr == nil {
		return ErrIO
	}
	rc := C.sqlite3_close(d.ptr)
	if rc != C.SQLITE_OK {
		// No caller can retain a statement; close_v2 still owns failed-close handles.
		C.sqlite3_close_v2(d.ptr)
	}
	d.ptr = nil
	return sqliteError(rc)
}
func (d *sqliteDB) prepare(sql string) (*sqliteStmt, error) {
	if len(sql) > 4096 {
		return nil, ErrInvalid
	}
	b := C.CString(sql)
	defer C.free(unsafe.Pointer(b))
	s := &sqliteStmt{}
	rc := C.sqlite3_prepare_v2(d.ptr, b, -1, &s.ptr, nil)
	if e := sqliteError(rc); e != nil {
		if s.ptr != nil {
			s.finish()
		}
		return nil, e
	}
	if s.ptr == nil {
		return nil, ErrIO
	}
	return s, nil
}
func (s *sqliteStmt) finish() error {
	if s.ptr == nil {
		return ErrIO
	}
	rc := C.sqlite3_finalize(s.ptr)
	s.ptr = nil
	return sqliteError(rc)
}
func (s *sqliteStmt) bind(numbers []int64, payload []byte) error {
	for i, n := range numbers {
		if e := sqliteError(C.sqlite3_bind_int64(s.ptr, C.int(i+1), C.sqlite3_int64(n))); e != nil {
			return e
		}
	}
	if payload != nil {
		if len(payload) == 0 || len(payload) > maxFixture {
			return ErrInvalid
		}
		copy := C.CBytes(payload)
		rc := C.bind_bytes(s.ptr, C.int(len(numbers)+1), copy, C.int(len(payload)))
		C.free(copy)
		return sqliteError(rc)
	}
	return nil
}
func (s *sqliteStmt) step() (bool, error) {
	rc := C.sqlite3_step(s.ptr)
	if rc == C.SQLITE_ROW {
		return true, nil
	}
	if rc == C.SQLITE_DONE {
		return false, nil
	}
	return false, sqliteError(rc)
}
func (s *sqliteStmt) values() ([]sqliteValue, error) {
	n := int(C.sqlite3_column_count(s.ptr))
	if n > 8 {
		return nil, ErrInvalid
	}
	out := make([]sqliteValue, n)
	for i := range out {
		v := &out[i]
		col := C.int(i)
		v.kind = int(C.sqlite3_column_type(s.ptr, col))
		switch v.kind {
		case sqlInteger:
			v.number = int64(C.sqlite3_column_int64(s.ptr, col))
		case sqlText, sqlBlob:
			size := C.sqlite3_column_bytes(s.ptr, col)
			if size < 0 || size > maxFixture {
				return nil, ErrInvalid
			}
			p := C.sqlite3_column_blob(s.ptr, col)
			if size > 0 && p == nil {
				return nil, ErrIO
			}
			v.bytes = C.GoBytes(p, size)
		case sqlNull:
		default:
			return nil, ErrInvalid
		}
	}
	return out, nil
}
func (d *sqliteDB) rows(sql string, limit int) ([][]sqliteValue, error) {
	s, e := d.prepare(sql)
	if e != nil {
		return nil, e
	}
	rows := [][]sqliteValue{}
	for {
		yes, err := s.step()
		if err != nil {
			s.finish()
			return nil, err
		}
		if !yes {
			break
		}
		if len(rows) == limit {
			s.finish()
			return nil, ErrInvalid
		}
		row, err := s.values()
		if err != nil {
			s.finish()
			return nil, err
		}
		rows = append(rows, row)
	}
	if e = s.finish(); e != nil {
		return nil, e
	}
	return rows, nil
}
func (d *sqliteDB) exec(sql string, numbers []int64, payload []byte) error {
	s, e := d.prepare(sql)
	if e != nil {
		return e
	}
	if e = s.bind(numbers, payload); e == nil {
		var row bool
		row, e = s.step()
		if row && e == nil {
			e = ErrInvalid
		}
	}
	end := s.finish()
	if e != nil {
		return e
	}
	return end
}
func (d *sqliteDB) changed() int      { return int(C.sqlite3_changes(d.ptr)) }
func (d *sqliteDB) autocommit() bool  { return C.sqlite3_get_autocommit(d.ptr) != 0 }
func (d *sqliteDB) cacheflush() error { return sqliteError(C.sqlite3_db_cacheflush(d.ptr)) }
func sqliteVersion() (string, string) {
	return C.GoString(C.sqlite3_libversion()), C.GoString(C.sqlite3_sourceid())
}

func sqliteExtensionOmitted() bool {
	option := C.CString("OMIT_LOAD_EXTENSION")
	defer C.free(unsafe.Pointer(option))
	return C.sqlite3_compileoption_used(option) == 1
}
