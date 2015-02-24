=head1 NAME

DB::Easy - A simple database object

=head1 DESCRIPTION

This library makes database usage easy. It uses DBI and SQL::Abstract
and presents a simple interface for manipulating SQL databases.

In addition to having convenience wrappers, it allows direct access to
the DBI database handler and SQL::Abstract instance as the 'dbh' and 'sql' 
object properties.

=head1 USAGE

  use DB::Easy;
  my $db = DB::Easy->new(type => 'mysql', db => 'test', user => 'myuser');
  my @results = $db->select('mytable', where => { id => 'gil' });

=cut

package DB::Easy;

our $VERSION = v2.0.0;

use v5.12;
use Moo;

use DBI;
use SQL::Abstract;
use Carp;

## A subroutine, looks for an argument in a hash.
sub getarg
{
  my ($opts, $name, $default) = @_;
  if (exists $opts->{$name} && defined $opts->{$name})
  {
    return $opts->{$name};
  }
  elsif (defined $default && $default eq '!REQUIRED')
  {
    croak "Required parameter '$name', not specified";
  }
  else
  {
    return $default;
  }
}

=head1 PUBLIC METHODS

=over 1

=item new(...)

Creates a database object, and connects to the database.

  my $db = Huri::DB->new(user => $username, pass => $password, db => $dbname);

Recognized options:

  type => $type               # database type, defaults to 'mysql'
  db   => $dbname             # name of database, mandatory.
  host => $hostname           # hostname, defaults to 'localhost'.
  port => $port               # server port, uses type-specific defaults.
  user => $username           # database user, required for most DBs.
  pass => $password           # database password, if required.

=cut

has 'type' =>
(
  is      => 'ro',
  default => sub { 'mysql' },
);

has 'db' =>
(
  is       => 'ro',
  required => 1,
);

has 'host' =>
(
  is      => 'ro',
  default => sub { '' },
);

has 'port' =>
(
  is      => 'ro',
  default => sub { 0; }
);

has 'user' =>
(
  is => 'rw',
);

has 'pass' =>
(
  is => 'rw',
);

has 'dsn' =>
(
  is => 'lazy',
);

has 'dbh' =>
(
  is => 'lazy',
);

has 'sql' =>
(
  is => 'lazy',
);

sub _build_dsn
{
  my ($self) = @_;
  my $type = $self->type;
  my $host = $self->host;
  my $port = $self->port;
  my $db   = $self->db;

  my $dsn = "DBI:$type:";

  no warnings;
  for ($type)
  {
    when ('SQLite')
    {
      $dsn .= "dbname=$db";
    }
    default
    {
      $dsn .= "database=$db";
      if ($host)
      {
        $dsn .= ";host=$host";
      }
      if ($port)
      {
        $dsn .= ";port=$port";
      }
    }
  }
  return $dsn;
}

sub _build_dbh
{
  my ($self) = @_;
  return DBI->connect($self->dsn, $self->user, $self->pass)
    || croak "Could not connect to database.";
}

sub _build_sql
{
  return SQL::Abstract->new();
}

sub _ensure_db
{
  my ($self) = @_;
  if (!$self->dbh->ping)
  {
    $self->{dbh} = $self->dbh->clone()
      or croak "Could not connect to database.";
  }
}

## private method DESTROY
## called when object is destroyed.

sub DEMOLISH
{
  my ($self) = @_;
  $self->dbh->disconnect;
}

=item select(...);

Performs a select statement, and returns the results in a requested format.

  my @rows = $db->select($table, where => { id => 17 });

Recognized options:

  where   => $hashref     A hash reference representing the WHERE statement.
  get     => $arrayref    The fields to get, defaults to all (*).
  order   => $arrayref    The sorting order to use.
  index   => $field       Return a hash ref, with $field as the index key.
  limit   => $number      Limit the results to a certain number of rows.
  offset  => $number      Used with limit to specify the starting position.
  return  => $field       Return a single field value, assumes limit => 1.
  build   => $boolean     If true, we return ($stmt, @bind) with no execute().
  prepare => $boolean     Like build, but returns a prepared statement.

=cut

sub select
{
  my ($self, $table, %opts) = @_;

  my $where  = getarg(\%opts, 'where'   );
  my $order  = getarg(\%opts, 'order'   );
  my $fields = getarg(\%opts, 'get', '*');

  my $limit;
  if (exists $opts{limit}) { $limit = $opts{limit}; }
  elsif (exists $opts{return}) { $limit = 1; }

  my ($stmt, @bind) = $self->sql->select($table, $fields, $where, $order);

  if ($limit)
  {
    $stmt .= " LIMIT $limit";
    if (exists $opts{offset})
    {
      $stmt .= " OFFSET " . $opts{offset};
    }
  }

  if (exists $opts{build} && $opts{build})
  {
    return ($stmt, @bind);
  }
  elsif (exists $opts{prepare} && $opts{prepare})
  {
    $self->_ensure_db;
    return $self->dbh->prepare($stmt);
  }

  my $sth = $self->execute($stmt, @bind);
  ## Now, the return format.
  if (exists $opts{index})
  {
    my $result = $sth->fetchall_hashref($opts{index});
    if (wantarray) { return %{$result}; }
    return $result;
  }
  elsif (exists $opts{return})
  {
    my $row = $sth->fetchrow_hashref;
    if (defined $row)
    {
      return $row->{$opts{return}};
    }
    else { return; } ## Empty, return nothing.
  }
  else
  {
    my $result = $sth->fetchall_arrayref({});
    if (wantarray) { return @{$result}; }
    return $result;
  }
  ## We should never reach here.
  return;
}

=item insert($table, ...)

Inserts a new record into the database.

  $self->insert('staff', id => 'gil', name => 'Gil Grisson', office => 'Las Vegas');

Returns the DBI statement handler.

=cut

sub insert
{
  my ($self, $table, %fields) = @_;
  if (!%fields) { croak "The insert() method requires fields to insert"; }
  my ($stmt, @bind) = $self->sql->insert($table, \%fields);
  my $sth = $self->execute($stmt, @bind);
  return $sth;
}

=item update($table, ...)

Updates data in an existing record.

Recognized options:

  set => $hashref         A hashref of values to set. Required!
  where => $hashref       A hashref representing the where statement.

Returns the DBI statement handler.

=cut

sub update
{
  my ($self, $table, %opts) = @_;
  my $fields = getarg(\%opts, 'set', '!REQUIRED');
  my $where  = getarg(\%opts, 'where');
  my ($stmt, @bind) = $self->sql->update($table, $fields, $where);
  my $sth = $self->execute($stmt, @bind);
  return $sth;
}

=item delete($table, ...);

Deletes a record from the database. All options are used as a where statement.

  $self->delete('staff', id => 'catherine');

Returns the DBI statement handler.

=cut

sub delete
{
  my ($self, $table, %where) = @_;
  if (!%where) { croak "The delete() method requires a where statement"; }
  my ($stmt, @bind) = $self->sql->delete($table, \%where);
  my $sth = $self->execute($stmt, @bind);
  return $sth;
}

=item execute($sql_statement, @sql_binding);

Executes a statement with associated bindings as returned from SQL::Abstract.

Returns the DBI statement handler.

=cut

sub execute
{
  my ($self, $stmt, @bind) = @_;
  $self->_ensure_db;
  my $sth = $self->dbh->prepare($stmt);
  $sth->execute(@bind);
  return $sth;
}

## End of methods

=back

=head1 DEPENDENCIES

Perl 5.12 or higher

DBI (and necessary database connectors)

SQL::Abstract

=head1 BUGS AND LIMITATIONS

It's a fairly simple library, and doesn't support every option under the sun.
What it does do, it does well. If you find bugs, let me know.

=head1 AUTHOR

Timothy Totten <2010@huri.net>

=head1 LICENSE

Artistic License 2.0

=cut

## End of package.
1;