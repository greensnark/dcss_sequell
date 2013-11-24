# A simple mapping of keys to arrays of values.
package Henzell::SQLLearnDB;

use strict;
use warnings;

use lib '..';
use parent 'Henzell::SQLite';

use File::Basename;
use File::Spec;

my $schema = File::Spec->catfile(dirname(__FILE__), '../../config/learndb.sql');

sub dbh {
  my $self = shift;
  my $db = $self->db();
  unless ($self->{initialized}) {
    $self->_initialize_db();
    $self->{initialized} = 1;
  }
  $db
}

sub init {
  shift()->dbh()
}

sub _valid_db {
  my $self = shift;
  $self->has_table('terms') && $self->has_table('definitions')
}

sub _initialize_db {
  my $self = shift;
  return if $self->_valid_db();
  $self->load_sql_file($schema);
  unless ($self->_valid_db()) {
    die "Could not initialize DB: ${ \ $self->file() }\n";
  }
}

sub each_term {
  my ($self, $action) = @_;
  $self->init();
  my $st = $self->prepare('SELECT term FROM terms');
  $st->execute();
  while (my $row = $st->fetchrow_arrayref()) {
    $action->($row->[0]);
  }
}

sub definitions {
  my ($self, $term) = @_;
  $self->init();
  my $st = $self->prepare(<<QUERY);
SELECT definition FROM definitions
 WHERE term_id = (SELECT id FROM terms WHERE term = ?)
ORDER BY seq ASC
QUERY
  $st->execute($term) or die "Couldn't lookup definition: $self->errstr()\n";
  my @definitions;
  while (my $row = $st->fetchrow_arrayref()) {
    push @definitions, $row->[0];
  }
  @definitions
}

sub definition {
  my ($self, $term, $index) = @_;
  $index ||= 1;
  my $defcount = $self->definition_count($term);
  $index += $defcount + 1 if $index < 0;
  $index = $defcount if $index > $defcount;
  return if $index < 0;
  $self->query_val(<<QUERY, $term, $index)
SELECT definition FROM definitions
 WHERE term_id = (SELECT id FROM terms WHERE term = ?)
   AND seq = ?
QUERY
}

sub term_id {
  my ($self, $term) = @_;
  $self->init();
  $self->query_val(<<QUERY, $term)
SELECT id FROM terms WHERE term = ?
QUERY
}

sub has_term {
  my ($self, $term) = @_;
  $self->init();
  $self->term_id($term)
}

sub definition_count {
  my ($self, $term) = @_;
  $self->init();
  if (defined($term)) {
    $self->query_val(<<QUERY, $term)
SELECT COUNT(*) FROM definitions
 WHERE term_id = (SELECT id FROM terms WHERE term = ?)
QUERY
  } else {
    $self->query_val('SELECT COUNT(*) FROM definitions')
  }
}

sub term_count {
  my $self = shift;
  $self->init();
  $self->query_val('SELECT COUNT(*) FROM terms')
}

sub has_definition {
  my ($self, $term) = @_;
  $self->init();
  $self->definition_count($term)
}

sub remove {
  my ($self, $term, $index) = @_;
  my $db = $self->dbh();

  $index ||= -1;
  if ($index == -1) {
    $self->exec('DELETE FROM terms WHERE term = ?', $term);
  } else {
    $self->begin_work;
    $self->exec(<<DELETE_VALUE, $term, $index);
DELETE FROM definitions
 WHERE term_id = (SELECT id FROM terms WHERE term = ?)
   AND seq = ?
DELETE_VALUE

    $self->exec(<<UPDATE_INDICES, $term, $index);
UPDATE definitions SET seq = seq - 1
 WHERE term_id = (SELECT id FROM terms WHERE term = ?)
   AND seq > ?
UPDATE_INDICES
    unless ($self->has_definition($term)) {
      $self->remove($term, -1);
    }
    $self->commit;
  }
}

sub update_value {
  my ($self, $term, $index, $value) = @_;
  $self->init();
  $self->exec(<<UPDATE_DEF, $value, $term, $index)
UPDATE definitions SET definition = ?
 WHERE term_id = (SELECT id FROM terms WHERE term = ?)
   AND seq = ?
UPDATE_DEF
}

sub update_term {
  my ($self, $term, $newterm) = @_;
  if ($self->has_term($newterm)) {
    die "Cannot rename $term -> $newterm, $newterm exists\n";
  }
  $self->exec(<<UPDATE_TERM, $newterm, $term)
UPDATE terms SET term = ? WHERE term = ?
UPDATE_TERM
}

sub add {
  my ($self, $term, $value, $index) = @_;
  my $db = $self->dbh();
  $self->begin_work() or die "Couldn't open transaction: $db->errstr\n";

  my $term_id = $self->term_id($term);
  unless ($term_id) {
    $self->exec('INSERT INTO terms (term) VALUES (?)', $term);
    $term_id = $db->last_insert_id(undef, undef, undef, undef) or
      die "Couldn't determine term id\n";
  }

  my $entry_count =
    $self->query_val('SELECT MAX(seq) FROM definitions WHERE term_id = ?',
                     $term_id);

  if (!defined($index)) {
    $index = ($entry_count || 0) + 1;
  } else {
    $index = 1 if $index <= 0 || !$entry_count;
    if ($entry_count) {
      $index = $entry_count + 1 if $index > $entry_count;
      if ($index <= $entry_count) {
        $self->exec(<<UPDATE_INDICES, $term_id, $index)
UPDATE definitions SET seq = seq + 1
 WHERE term_id = ? AND seq >= ?
UPDATE_INDICES
      }
    }
  }
  $self->exec(<<INSERT_SQL, $term_id, $value, $index);
INSERT INTO definitions (term_id, definition, seq)
     VALUES (?, ?, ?)
INSERT_SQL
  $self->commit();

  $index
}

1
