#!/usr/bin/env perl

use Test::More tests => 1;

BEGIN {
	use_ok( 'App::ZofCMS::Plugin::FormChecker' );
}

diag( "Testing App::ZofCMS::Plugin::FormChecker $App::ZofCMS::Plugin::FormChecker::VERSION, Perl $], $^X" );
