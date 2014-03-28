#!/usr/bin/perl

use v5.12;
use strict;
use warnings;
use lib qw(lib);
use Test::More; # tests => 2;

require_ok "DB::Easy";

my $dbfile = ".test.sqlite";

my $class = "DB::Easy";

my $db = new_ok($class => [type => 'SQLite', db => $dbfile]);

ok $db->dbh->do("CREATE TABLE a ( id INTEGER PRIMARY KEY, name TEXT, weight REAL)"), "CREATE TABLE";

ok $db->insert('a', name => "Bob",    weight => 1.5)
&& $db->insert('a', name => "Kelly",  weight => 2.3)
&& $db->insert('a', name => "Alex",   weight => 0.7),
"Insert sample data";

my $users;
ok $users = $db->select('a', where => {id => 1}), "select user"; 

is scalar @$users, 1, 'correct number of users returned';

my $user = $users->[0];

is $user->{name}, 'Bob', 'returned correct user';

ok $users = $db->select('a', where => {weight => {'>' => 1}}), "select users with custom comparison";

is scalar @$users, 2, 'correct number of users returned';

#diag explain $users;

## TODO: more tests

## Cleanup
unlink $dbfile;

done_testing();
