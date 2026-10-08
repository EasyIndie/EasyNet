//go:build darwin && cgo

package statelab

const sqliteName = "state.sqlite"
const sqliteJournal = "state.sqlite-journal"
const sqliteDDL = `CREATE TABLE state_snapshot (
  singleton ANY PRIMARY KEY CHECK(typeof(singleton)='integer' AND singleton=1),
  schema_version ANY NOT NULL CHECK(typeof(schema_version)='integer' AND schema_version BETWEEN 0 AND 2147483647),
  generation ANY NOT NULL CHECK(typeof(generation)='integer' AND generation BETWEEN 0 AND 2147483647),
  payload ANY NOT NULL CHECK(typeof(payload)='blob' AND length(payload) BETWEEN 1 AND 16384)
) STRICT`
const sqliteRead = "SELECT singleton,schema_version,generation,payload FROM state_snapshot LIMIT 2"
const sqliteInsert = "INSERT INTO state_snapshot(singleton,schema_version,generation,payload) VALUES(1,?,?,?)"

// The BLOB is last so the common native binder never retains Go memory.
const sqliteUpdate = "UPDATE state_snapshot SET schema_version=?1,generation=?2,payload=?5 WHERE singleton=1 AND schema_version=?3 AND generation=?4"
const sqliteNoop = "UPDATE state_snapshot SET payload=payload WHERE singleton=1"

func textValue(v sqliteValue, want string) bool  { return v.kind == sqlText && string(v.bytes) == want }
func numberValue(v sqliteValue, want int64) bool { return v.kind == sqlInteger && v.number == want }
func (d *sqliteDB) scalar(sql string, want sqliteValue) error {
	rows, e := d.rows(sql, 1)
	if e != nil {
		return e
	}
	if len(rows) != 1 || len(rows[0]) != 1 {
		return ErrInvalid
	}
	got := rows[0][0]
	if got.kind != want.kind || got.number != want.number || string(got.bytes) != string(want.bytes) {
		return ErrInvalid
	}
	return nil
}
func integerSetting(n int64) sqliteValue { return sqliteValue{kind: sqlInteger, number: n} }
func textSetting(s string) sqliteValue   { return sqliteValue{kind: sqlText, bytes: []byte(s)} }
func (d *sqliteDB) settings(writable, seed bool) error {
	if writable {
		if seed {
			if e := d.exec("PRAGMA page_size=4096", nil, nil); e != nil {
				return e
			}
		}
		// PRAGMA journal_mode returns its mode; consume and verify its result.
		if e := d.scalar("PRAGMA journal_mode=DELETE", textSetting("delete")); e != nil {
			return e
		}
		for _, sql := range []string{"PRAGMA synchronous=EXTRA", "PRAGMA fullfsync=ON", "PRAGMA temp_store=MEMORY", "PRAGMA mmap_size=0", "PRAGMA locking_mode=NORMAL"} {
			// mmap_size and locking_mode return one value, unlike assignments above.
			if sql == "PRAGMA mmap_size=0" {
				if e := d.scalar(sql, integerSetting(0)); e != nil {
					return e
				}
			} else if sql == "PRAGMA locking_mode=NORMAL" {
				if e := d.scalar(sql, textSetting("normal")); e != nil {
					return e
				}
			} else if e := d.exec(sql, nil, nil); e != nil {
				return e
			}
		}
	}
	checks := []struct {
		sql  string
		want sqliteValue
	}{
		{"PRAGMA page_size", integerSetting(4096)},
		{"PRAGMA journal_mode", textSetting("delete")},
		{"PRAGMA mmap_size", integerSetting(0)},
		{"PRAGMA locking_mode", textSetting("normal")},
		{"PRAGMA busy_timeout", integerSetting(1000)},
	}
	if writable {
		checks = append(checks, struct {
			sql  string
			want sqliteValue
		}{"PRAGMA synchronous", integerSetting(3)}, struct {
			sql  string
			want sqliteValue
		}{"PRAGMA fullfsync", integerSetting(1)}, struct {
			sql  string
			want sqliteValue
		}{"PRAGMA temp_store", integerSetting(2)})
	}
	for _, c := range checks {
		if e := d.scalar(c.sql, c.want); e != nil {
			return e
		}
	}
	return nil
}
func (d *sqliteDB) schema() error {
	rows, e := d.rows("SELECT type,name,tbl_name,sql FROM sqlite_schema LIMIT 3", 3)
	if e != nil {
		return e
	}
	if len(rows) != 2 {
		return ErrInvalid
	}
	table, index := false, false
	for _, r := range rows {
		if len(r) != 4 || !textValue(r[2], "state_snapshot") {
			return ErrInvalid
		}
		switch {
		case textValue(r[0], "table") && textValue(r[1], "state_snapshot") && textValue(r[3], sqliteDDL):
			if table {
				return ErrInvalid
			}
			table = true
		case textValue(r[0], "index") && textValue(r[1], "sqlite_autoindex_state_snapshot_1") && r[3].kind == sqlNull:
			if index {
				return ErrInvalid
			}
			index = true
		default:
			return ErrInvalid
		}
	}
	if !table || !index {
		return ErrInvalid
	}
	cols, e := d.rows("PRAGMA table_xinfo(state_snapshot)", 4)
	if e != nil {
		return e
	}
	if len(cols) != 4 {
		return ErrInvalid
	}
	for i, name := range []string{"singleton", "schema_version", "generation", "payload"} {
		r := cols[i]
		pk := int64(0)
		if i == 0 {
			pk = 1
		}
		if len(r) != 7 || !numberValue(r[0], int64(i)) || !textValue(r[1], name) || !textValue(r[2], "ANY") || !numberValue(r[3], 1) || r[4].kind != sqlNull || !numberValue(r[5], pk) || !numberValue(r[6], 0) {
			return ErrInvalid
		}
	}
	form, e := d.rows("SELECT schema,name,type,ncol,wr,strict FROM pragma_table_list WHERE name='state_snapshot' LIMIT 2", 2)
	if e != nil {
		return e
	}
	if len(form) != 1 || len(form[0]) != 6 {
		return ErrInvalid
	}
	r := form[0]
	if !textValue(r[0], "main") || !textValue(r[1], "state_snapshot") || !textValue(r[2], "table") || !numberValue(r[3], 4) || !numberValue(r[4], 0) || !numberValue(r[5], 1) {
		return ErrInvalid
	}
	return nil
}
func (d *sqliteDB) readSnapshot(r Resolver, integrity bool) (Snapshot, error) {
	if e := d.schema(); e != nil {
		return Snapshot{}, e
	}
	rows, e := d.rows(sqliteRead, 2)
	if e != nil {
		return Snapshot{}, e
	}
	if len(rows) != 1 || len(rows[0]) != 4 {
		return Snapshot{}, ErrInvalid
	}
	row := rows[0]
	if !numberValue(row[0], 1) || row[1].kind != sqlInteger || row[2].kind != sqlInteger || row[3].kind != sqlBlob {
		return Snapshot{}, ErrInvalid
	}
	if row[1].number < 0 || row[1].number > int64(MaxGeneration) || row[2].number < 0 || row[2].number > int64(MaxGeneration) || len(row[3].bytes) < 1 || len(row[3].bytes) > maxFixture {
		return Snapshot{}, ErrInvalid
	}
	if integrity {
		if e := d.scalar("PRAGMA integrity_check(1)", textSetting("ok")); e != nil {
			if e == ErrInvalid {
				e = ErrCorrupt
			}
			return Snapshot{}, e
		}
	}
	snap, e := DecodeFixture(row[3].bytes)
	if e != nil {
		return Snapshot{}, e
	}
	if int64(snap.SchemaVersion) != row[1].number || int64(snap.Generation) != row[2].number {
		return Snapshot{}, ErrCorrupt
	}
	if _, e = EncodeFixture(snap, r); e != nil {
		return Snapshot{}, e
	}
	return snap, nil
}
