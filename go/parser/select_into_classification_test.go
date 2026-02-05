// PostgreSQL Database Management System
// (also known as Postgres, formerly known as Postgres95)
//
//	Portions Copyright (c) 2025, Supabase, Inc
//
//	Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
//
//	Portions Copyright (c) 1994, The Regents of the University of California
//
// Permission to use, copy, modify, and distribute this software and its
// documentation for any purpose, without fee, and without a written agreement
// is hereby granted, provided that the above copyright notice and this
// paragraph and the following two paragraphs appear in all copies.
//
// IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
// DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING
// LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS
// DOCUMENTATION, EVEN IF THE UNIVERSITY OF CALIFORNIA HAS BEEN ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
// INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
// AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
// ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATIONS TO
// PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.

package parser

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/multigres/multigres/go/parser/ast"
)

// TestSelectFromVsSelectInto verifies that the parser correctly distinguishes
// between SELECT ... FROM (a read query) and SELECT ... INTO (a DDL that
// creates a new table — legacy PostgreSQL syntax equivalent to CREATE TABLE AS).
func TestSelectFromVsSelectInto(t *testing.T) {
	t.Run("SELECT FROM is a plain read query", func(t *testing.T) {
		stmts, err := ParseSQL("SELECT * FROM tbl")
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		sel, ok := stmts[0].(*ast.SelectStmt)
		require.True(t, ok, "expected SelectStmt, got %T", stmts[0])

		assert.Nil(t, sel.IntoClause, "plain SELECT should have no IntoClause")
		assert.Equal(t, "SELECT", sel.StatementType())
	})

	t.Run("SELECT INTO is a table-creating statement", func(t *testing.T) {
		stmts, err := ParseSQL("SELECT * INTO new_tbl FROM src_tbl")
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		sel, ok := stmts[0].(*ast.SelectStmt)
		require.True(t, ok, "expected SelectStmt, got %T", stmts[0])

		assert.Equal(t, "SELECT INTO", sel.StatementType(),
			"SELECT INTO must NOT be classified as a plain SELECT — it creates a table")
		require.NotNil(t, sel.IntoClause, "SELECT INTO must have IntoClause")
		require.NotNil(t, sel.IntoClause.Rel, "IntoClause must have a target relation")
		assert.Equal(t, "new_tbl", sel.IntoClause.Rel.RelName)
	})

	t.Run("SELECT INTO TABLE is equivalent to SELECT INTO", func(t *testing.T) {
		stmts, err := ParseSQL("SELECT * INTO TABLE new_tbl FROM src_tbl")
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		sel, ok := stmts[0].(*ast.SelectStmt)
		require.True(t, ok, "expected SelectStmt, got %T", stmts[0])

		assert.Equal(t, "SELECT INTO", sel.StatementType())
		require.NotNil(t, sel.IntoClause, "SELECT INTO TABLE must have IntoClause")
		assert.Equal(t, "new_tbl", sel.IntoClause.Rel.RelName)
	})

	t.Run("CREATE TABLE AS SELECT produces CreateTableAsStmt", func(t *testing.T) {
		stmts, err := ParseSQL("CREATE TABLE new_tbl AS SELECT * FROM src_tbl")
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		ctas, ok := stmts[0].(*ast.CreateTableAsStmt)
		require.True(t, ok, "expected CreateTableAsStmt, got %T", stmts[0])

		assert.False(t, ctas.IsSelectInto, "CREATE TABLE AS should not be marked as SELECT INTO")
		assert.Equal(t, "CREATE TABLE AS", ctas.StatementType())
		require.NotNil(t, ctas.Into)
		assert.Equal(t, "new_tbl", ctas.Into.Rel.RelName)

		// The inner query should be a plain SelectStmt with no IntoClause
		innerSel, ok := ctas.Query.(*ast.SelectStmt)
		require.True(t, ok, "inner query should be SelectStmt, got %T", ctas.Query)
		assert.Nil(t, innerSel.IntoClause, "inner SELECT in CREATE TABLE AS should have no IntoClause")
	})

	t.Run("SELECT with columns INTO creates a table", func(t *testing.T) {
		stmts, err := ParseSQL("SELECT id, name INTO new_tbl FROM users WHERE active = true")
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		sel, ok := stmts[0].(*ast.SelectStmt)
		require.True(t, ok, "expected SelectStmt, got %T", stmts[0])

		assert.Equal(t, "SELECT INTO", sel.StatementType())
		require.NotNil(t, sel.IntoClause, "SELECT cols INTO must have IntoClause")
		assert.Equal(t, "new_tbl", sel.IntoClause.Rel.RelName)

		// Should still have FROM clause
		require.NotNil(t, sel.FromClause)
		assert.Greater(t, sel.FromClause.Len(), 0, "should have FROM clause items")
	})

	t.Run("SELECT INTO TEMP TABLE creates a temporary table", func(t *testing.T) {
		stmts, err := ParseSQL("SELECT * INTO TEMP TABLE tmp_tbl FROM src_tbl")
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		sel, ok := stmts[0].(*ast.SelectStmt)
		require.True(t, ok, "expected SelectStmt, got %T", stmts[0])

		assert.Equal(t, "SELECT INTO", sel.StatementType())
		require.NotNil(t, sel.IntoClause, "SELECT INTO TEMP must have IntoClause")
		assert.Equal(t, "tmp_tbl", sel.IntoClause.Rel.RelName)
		assert.Equal(t, ast.RELPERSISTENCE_TEMP, sel.IntoClause.Rel.RelPersistence,
			"TEMP table should be marked with RELPERSISTENCE_TEMP")
	})

	t.Run("schema-qualified SELECT INTO", func(t *testing.T) {
		stmts, err := ParseSQL("SELECT * INTO myschema.new_tbl FROM src_tbl")
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		sel, ok := stmts[0].(*ast.SelectStmt)
		require.True(t, ok, "expected SelectStmt, got %T", stmts[0])

		assert.Equal(t, "SELECT INTO", sel.StatementType())
		require.NotNil(t, sel.IntoClause)
		assert.Equal(t, "new_tbl", sel.IntoClause.Rel.RelName)
		assert.Equal(t, "myschema", sel.IntoClause.Rel.SchemaName)
	})

	t.Run("round-trip: SELECT FROM stays as SELECT FROM", func(t *testing.T) {
		input := "SELECT a, b FROM tbl WHERE a > 1"
		stmts, err := ParseSQL(input)
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		assert.Equal(t, "SELECT", stmts[0].StatementType())
		output := stmts[0].SqlString()

		// Re-parse the output
		stmts2, err := ParseSQL(output)
		require.NoError(t, err)
		require.Len(t, stmts2, 1)

		sel2, ok := stmts2[0].(*ast.SelectStmt)
		require.True(t, ok)
		assert.Nil(t, sel2.IntoClause, "round-tripped SELECT FROM should still have no IntoClause")
		assert.Equal(t, "SELECT", sel2.StatementType())
	})

	t.Run("round-trip: SELECT INTO stays as SELECT INTO", func(t *testing.T) {
		input := "SELECT * INTO new_tbl FROM src_tbl WHERE id > 100"
		stmts, err := ParseSQL(input)
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		assert.Equal(t, "SELECT INTO", stmts[0].StatementType())
		output := stmts[0].SqlString()

		// Re-parse the output
		stmts2, err := ParseSQL(output)
		require.NoError(t, err)
		require.Len(t, stmts2, 1)

		sel2, ok := stmts2[0].(*ast.SelectStmt)
		require.True(t, ok)
		require.NotNil(t, sel2.IntoClause, "round-tripped SELECT INTO must still have IntoClause")
		assert.Equal(t, "new_tbl", sel2.IntoClause.Rel.RelName)
		assert.Equal(t, "SELECT INTO", sel2.StatementType())
	})
}

// TestSelectIntoIsNotInsertInto confirms that SELECT INTO (table creation) is
// structurally different from INSERT INTO (data insertion into existing table).
func TestSelectIntoIsNotInsertInto(t *testing.T) {
	t.Run("INSERT INTO is an InsertStmt", func(t *testing.T) {
		stmts, err := ParseSQL("INSERT INTO tbl (col) VALUES (1)")
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		_, ok := stmts[0].(*ast.InsertStmt)
		assert.True(t, ok, "INSERT INTO should produce InsertStmt, got %T", stmts[0])
		assert.Equal(t, "INSERT", stmts[0].StatementType())
	})

	t.Run("SELECT INTO is a SelectStmt with IntoClause", func(t *testing.T) {
		stmts, err := ParseSQL("SELECT 1 INTO tbl")
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		sel, ok := stmts[0].(*ast.SelectStmt)
		assert.True(t, ok, "SELECT INTO should produce SelectStmt, got %T", stmts[0])
		assert.Equal(t, "SELECT INTO", stmts[0].StatementType())
		require.NotNil(t, sel.IntoClause)
	})
}

// TestCreateMaterializedViewVsSelectInto checks that CREATE MATERIALIZED VIEW
// is distinguished from SELECT INTO and CREATE TABLE AS.
func TestCreateMaterializedViewVsSelectInto(t *testing.T) {
	t.Run("CREATE MATERIALIZED VIEW has its own statement type", func(t *testing.T) {
		stmts, err := ParseSQL("CREATE MATERIALIZED VIEW mv AS SELECT * FROM tbl")
		require.NoError(t, err)
		require.Len(t, stmts, 1)

		ctas, ok := stmts[0].(*ast.CreateTableAsStmt)
		require.True(t, ok, "expected CreateTableAsStmt, got %T", stmts[0])

		assert.Equal(t, ast.OBJECT_MATVIEW, ctas.ObjType)
		assert.Equal(t, "CREATE MATERIALIZED VIEW", ctas.StatementType())
		assert.False(t, ctas.IsSelectInto)
	})
}
