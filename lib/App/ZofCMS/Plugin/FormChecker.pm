package App::ZofCMS::Plugin::FormChecker;

use warnings;
use strict;

our $VERSION = '0.0101';

sub new { bless {}, shift }

sub process {
    my ( $self, $template, $query, $config ) = @_;

    return
        unless $template->{plug_form_checker}
            or $config->conf->{plug_form_checker};

    my %conf = (
        trigger => 'plug_form_checker',
        ok_key  => 'd',
        no_fill => 0,
        fill_prefix => 'plug_form_q_',
        %{ delete $template->{plug_form_checker}     || {} },
        %{ delete $config->conf->{plug_form_checker} || {} },
    );

    return
        unless $query->{ $conf{trigger} };

    keys %{ $conf{rules} };
    while ( my ( $param, $rule ) = each %{ $conf{rules} } ) {
        if ( not ref $rule ) {
            $rule = { $rule => 1 };
        }
        elsif ( ref $rule eq 'CODE' ) {
            $rule = { code => $rule };
        }
        elsif ( ref $rule eq 'Regexp' ) {
            $rule = { must_match => $rule };
        }
        elsif ( ref $rule eq 'ARRAY' ) {
            $rule = { map +( $_ => 1 ), @$rule };
        }

        last
            unless $self->_rule_ok( $param, $rule, $query->{ $param } );
    }

    unless ( $conf{no_fill} ) {
        my @rule_params = keys %{ $conf{rules} };
        my @select_params;
        while ( my ( $key, $value ) = each %{ $conf{rules} } ) {
            if ( ref $value eq 'HASH' and $value->{select} ) {
                push @select_params, $key;
            }
        }
        my @template_keys = map "$conf{fill_prefix}$_", @rule_params;
        @{ $template->{t} }{ @template_keys } = @$query{ @rule_params };
        if ( @select_params ) {
            @{ $template->{t} }{
                map "$conf{fill_prefix}${_}_$query->{$_}", @select_params
            } = (1) x @select_params;
        }
    }

    if ( defined(my $error = $self->_error) ) {
        $template->{t}{plug_form_checker_error} = $error;
    }
    else {
        $template->{ $conf{ok_key} }{plug_form_checker_ok} = 1;
        if ( exists $conf{ok_redirect} ) {
            print $config->cgi->redirect( $conf{ok_redirect} );
            exit;
        }
    }
}

sub _rule_ok {
    my ( $self, $param, $rule, $value ) = @_;

    my $name = defined $rule->{name} ? $rule->{name} : $param;

    unless ( defined $value and length $value ) {
        if ( $rule->{optional} ) {
            return 1;
        }
        else {
            return $self->_fail( $name, 'mandatory_error', $rule );
        }
    }

    if ( $rule->{num} ) {
        return $self->_fail( $name, 'num_error', $rule )
            if $value =~ /\D/;
    }

    return $self->_fail( $name, 'min_error', $rule )
        if defined $rule->{min}
            and length($value) < $rule->{min};

    return $self->_fail( $name, 'max_error', $rule )
        if defined $rule->{max}
            and length($value) > $rule->{max};

    if ( $rule->{must_match} ) {
        return $self->_fail( $name, 'must_match_error', $rule )
            if $value !~ /$rule->{must_match}/;
    }

    if ( $rule->{must_not_match} ) {
        return $self->_fail( $name, 'must_not_match_error', $rule )
            if $value =~ /$rule->{must_not_match}/;
    }

    if ( $rule->{code} ) {
        return $self->_fail( $name, 'code_error', $rule )
            unless $rule->{code}->( $value );
    }

    if ( my @values = @{ $rule->{valid_values} || [] } ) {
        my %valid;
        @valid{ @values} = (1) x @values;

        return $self->_fail( $name, 'valid_values_error', $rule )
            unless exists $valid{$value};
    }

    return 1;
}

sub _make_error {
    my ( $self, $name, $err_name, $rule ) = @_;

    return $rule->{ $err_name }
        if exists $rule->{ $err_name };
    
    my %errors = (
        mandatory_error   => "You must specify parameter $name",
        num_error         => "Parameter $name must contain digits only",
        min_error         => "Parameter $name must be at least $rule->{min} characters long",
        max_error         => "Parameter $name cannot be longer than $rule->{max} characters",
        code_error        => "Parameter $name contains incorrect data",
        must_match_error  => "Parameter $name contains incorrect data",
        must_not_match_error => "Parameter $name contains incorrect data",
        valid_values_error
            => "Parameter $name must be " . do {
                    my $last = pop @{ $rule->{valid_values} || [''] };
                    join(', ', @{ $rule->{valid_values} || [] } ) . " or $last"
        },
    );

    return $errors{ $err_name };
}

sub _fail {
    my ( $self, $name, $err_name, $rule ) = @_;

    $self->{FAIL} = $self->_make_error( $name, $err_name, $rule );
    return;
}

sub _error {
    return shift->{FAIL};
}


1;
__END__

=head1 NAME

App::ZofCMS::Plugin::FormChecker - plugin to check HTML form data.

=head1 SYNOPSIS

In ZofCMS template or main config file:

    plugins => [ qw/FormChecker/ ],
    plug_form_checker => {
        trigger     => 'some_param',
        ok_key      => 't',
        fill_prefix => 'form_checker_',
        rules       => {
            param1 => 'num',
            param2 => qr/foo|bar/,
            param3 => [ qw/optional num/ ],
            param4 => {
                optional        => 1,
                select          => 1,
                must_match      => qr/foo|bar/,
                must_not_match  => qr/foos/,
                must_match_error => 'Param4 must contain either foo or bar but not foos',
            },
            param5 => {
                valid_values        => [ qw/foo bar baz/ ],
                valid_values_error  => 'Param5 must be foo, bar or baz',
            },
            param6 => sub { time() % 2 }, # return true or false values
        },
    },

=head1 DESCRIPTION

The module is a plugin for L<App::ZofCMS> that provides nifteh form checking.

This documentation assumes you've read L<App::ZofCMS>, L<App::ZofCMS::Config> and
L<App::ZofCMS::Template>

=head1 ZofCMS TEMPLATE/MAIN CONFIG FILE FIRST LEVEL KEYS

The keys can be set either in ZofCMS template or in Main Config file, if same keys
are set in both, then the one in ZofCMS template takes precedence.

=head2 C<plugins>

    plugins => [ qw/FormChecker/ ],

You obviously would want to include the plugin in the list of plugins to execute.

=head2 C<plug_form_checker>

    # keys are listed for demostrative purposes,
    # some of these don't make sense when used together
    plug_form_checker => {
        trigger     => 'plug_form_checker',
        ok_key      => 'd',
        ok_redirect => '/some-page',
        no_fill     => 1,
        fill_prefix => 'plug_form_q_',
        rules       => {
            param1 => 'num',
            param2 => qr/foo|bar/,
            param3 => [ qw/optional num/ ],
            param4 => {
                optional        => 1,
                select          => 1,
                must_match      => qr/foo|bar/,
                must_not_match  => qr/foos/,
                must_match_error => 'Param4 must contain either foo or bar but not foos',
            },
            param5 => {
                valid_values        => [ qw/foo bar baz/ ],
                valid_values_error  => 'Param5 must be foo, bar or baz',
            },
            param6 => sub { time() % 2 }, # return true or false values
        },
    },

The C<plug_form_checker> first-level key takes a hashref as a value. Only the
C<rules> key is mandatory, the rest are optional. The possible
keys/values of that hashref are as follows.

=head3 C<trigger>

    trigger => 'plug_form_checker',

B<Optional>. Takes a string as a value that must contain the name of the query
parameter that would trigger checking of the form. Generally, it would be some
parameter of the form you are checking (that would always contain true value, in perl's sense
of true) or you could always use
C<< <input type="hidden" name="plug_form_checker" value="1"> >>. B<Defaults to:>
C<plug_form_checker>

=head3 C<ok_key>

    ok_key => 'd',

B<Optional>. If the form passed all the checks plugin will set a B<second level>
key C<plug_form_checker> to a true value. The C<ok_key> parameter specifies the
B<first level> key in ZofCMS template where to put the C<plug_form_checker> key. For example,
you can set C<ok_key> to C<'t'> and then in your L<HTML::Template> template use
C<< <tmpl_if name="plug_form_checker">FORM OK!</tmpl_if> >>... but, beware of using
the C<'t'> key when you are also using L<App::ZofCMS::QueryToTemplate> plugin, as someone
could avoid proper form checking by passing fake query parameter. B<Defaults to:>
C<d> ("data" ZofCMS template special key).

=head3 C<ok_redirect>

    ok_redirect => '/some-page',

B<Optional>. If specified, the plugin will automatically redirect the user to the
URL specified as a value to C<ok_redirect> key. Note that the plugin will C<exit()> right
after printing the redirect header. B<By default> not specified.

=head3 C<no_fill>

    no_fill => 1,

B<Optional>. When set to a true value plugin will not fill query values. B<Defaults to:> C<0>.
When C<no_fill> is set to a B<false> value the plugin will fill in
ZofCMS template's C<{t}> special key with query parameter values (only the ones that you
are checking, though, see C<rules> key below). This allows you to fill your form
with values that user already specified in case the form check failed. The names
of the keys inside the C<{t}> key will be formed as follows:
C<< $prefix . $query_param_name >> where C<$prefix> is the value of C<fill_prefix> key
(see below) and C<$query_param_name> is the name of the query parameter.
Of course, this alone wouldn't cut it for radio buttons or C<< <select> >>
elements. For that, you need to set C<< select => 1 >> in the ruleset for that particular
query parameter (see C<rules> key below); when C<select> rule is set to a true value then
the names of the keys inside the C<{t}> key will be formed as follows:
C<< $prefix . $query_param_name . '_' . $value >>. Where the C<$prefix> is the value
of C<fill_prefix> key, C<$query_param_name> is the name of the query parameter; following
is the underscore (C<_>) and then C<$value> that is the value of the query parameter. Consider
the following snippet in ZofCMS template and corresponding L<HTML::Template> HTML code as
an example:

    plug_form_checker => {
        trigger => 'foo',
        fill_prefix => 'plug_form_q_',
        rules => { foo => { select => 1 } },
    }

    <form action="" method="POST">
        <input type="text" name="bar" value="<tmpl_var name="plug_form_q_">">
        <input type="radio" name="foo" value="1"
            <tmpl_if name="plug_form_q_foo_1"> checked </tmpl_if>
        >
        <input type="radio" name="foo" value="2"
            <tmpl_if name="plug_form_q_foo_2"> checked </tmpl_if>
        >
    </form>

=head3 C<fill_prefix>

    fill_prefix => 'plug_form_q_',

B<Optional>. Specifies the prefix to use for keys in C<{t}> ZofCMS template special key
when C<no_fill> is set to a false value. The "filling" is described above in C<no_fill>
description. B<Defaults to:> C<plug_form_q_> (note the underscore at the very end)

=head3 C<rules>

        rules       => {
            param1 => 'num',
            param2 => qr/foo|bar/,
            param3 => [ qw/optional num/ ],
            param4 => {
                optional        => 1,
                select          => 1,
                must_match      => qr/foo|bar/,
                must_not_match  => qr/foos/,
                must_match_error => 'Param4 must contain either foo or bar but not foos',
            },
            param5 => {
                valid_values        => [ qw/foo bar baz/ ],
                valid_values_error  => 'Param5 must be foo, bar or baz',
            },
            param6 => sub { time() % 2 }, # return true or false values
        },

This is the "heart" of the plugin, the place where you specify the rules for checking.
The C<rules> key takes a hashref as a value. The keys of that hashref are the names
of the query parameters that you wish to check. The values of those keys are the
"rulesets". The values can be either a string, regex (C<qr//>), arrayref, subref or a hashref;
If the value is NOT a hashref it will be changed into hashref
as follows (the actual meaning of resulting hashrefs is described below):

=head4 a string

    param => 'num',
    # same as
    param => { num => 1 },

=head4 a regex

    param => qr/foo/,
    # same as
    param => { must_match => qr/foo/ },

=head4 an arrayref

    param => [ qw/optional num/ ],
    # same as
    param => {
        optional => 1,
        num      => 1,
    },

=head4 a subref

    param => sub { time() % 2 },
    # same as
    param => { code => sub { time() % 2 } },

=head3 C<rules> RULESETS

The rulesets (values of C<rules> hashref) have keys that define the type of the rule and
value defines diffent things or just indicates that the rule should be considered.
Here is the list of all valid ruleset keys:

    rules => {
        param => {
            name            => 'Parameter', # the name of this param to use in error messages
            num             => 1, # value must be numbers-only
            optional        => 1, # parameter is optional
            must_match      => qr/foo/, # value must match given regex
            must_not_match  => qr/bar/, # value must NOT match the given regex
            max             => 20, # value must not exceed 20 characters in length
            min             => 3,  # value must be more than 3 characters in length
            valid_values    => [ qw/foo bar baz/ ], # value must be one from the given list
            code            => sub { time() %2 }, # return from the sub determines pass/fail
            select          => 1, # flag for "filling", see no_fill key above
            num_error       => 'Numbers only!', # custom error if num rule failed
            mandatory_error => '', # same for if parameter is missing and not optional.
            must_match_error => '', # same for must_match rule
            must_not_match_error => '', # same for must_not_match_rule
            max_error            => '', # same for max rule
            min_error            => '', # same for min rule
            code_error           => '', # same for code rule
            valid_values_error   => '', # same for valid_values rule
        },
    }

You can mix and match the rules for perfect tuning.

=head4 C<name>

    name => 'Decent name',

This is not actually a rule but the text to use for the name of the parameter in error
messages. If not specified the actual parameter name will be used.

=head4 C<num>

    num => 1,

When set to a true value the query parameter's value must contain digits only.

=head4 C<optional>

    optional => 1,

When set to a true value indicates that the parameter is optional. Note that you can specify
other rules along with this one, e.g.:

    optional => 1,
    num      => 1,

Means, query parameter is optional, B<but if it is given> it must contain only digits.

=head4 C<must_match>

    must_match => qr/foo/,

Takes a regex (C<qr//>) as a value. The query parameter's value must match this regex.

=head4 C<must_not_match>

    must_not_match => qr/bar/,

Takes a regex (C<qr//>) as a value. The query parameter's value must B<NOT> match this regex.

=head4 C<max>

    max => 20,

Takes a positive integer as a value. Query parameter's value must not exceed C<max>
characters in length.

=head4 C<min>

    min => 3,

Takes a positive integer as a value. Query parameter's value must be at least C<min>
characters in length.

=head4 C<valid_values>

    valid_values => [ qw/foo bar baz/ ],

Takes an arrayref as a value. Query parameter's value must be one of the items in the arrayref.

=head4 C<code>

    code => sub { time() %2 },

Here you can let your soul dance to your desire. Takes a subref as a value. The C<@_> will
contain only one element - the value of the parameter that is being tested.
If the sub returns a true value - the check will be considered successfull. If the
sub returns a false value, then test fails and form check stops and errors.

=head4 C<select>

    select => 1,

This one is not actually a "rule". This is a flag for C<{t}> "filling" that is
described in great detail (way) above under the description of C<no_fill> key.

=head3 CUSTOM ERROR MESSAGES IN RULESETS

All C<*_error> keys take strings as values; they can be used to set custom error
messages for each test in the ruleset. In the defaults listed below under each C<*_error>,
the C<$name> represents either the name of the parameter or the value of C<name> key that
you set in the ruleset.

=head4 C<num_error>

    num_error => 'Numbers only!',

This will be the error to be displayed if C<num> test fails.
B<Defaults to> C<Parameter $name must contain digits only>.

=head4 C<mandatory_error>
 
    mandatory_error => 'Must gimme!',

This is the error when C<optional> is set to a false value, which is the default, and
user did not specify the query parameter. I.e., "error to display for missing mandatory
parameters". B<Defaults to:> C<You must specify parameter $name>

=head4 C<must_match_error>

    must_match_error => 'Must match me!',

This is the error for C<must_match> rule. B<Defaults to:>
C<Parameter $name contains incorrect data>

=head4 C<must_not_match_error>

    must_not_match_error => 'Cannot has me!',

This is the error for C<must_not_match> rule. B<Defaults to:>
C<Parameter $name contains incorrect data>

=head4 C<max_error>

    max_error => 'Too long!',

This is the error for C<max> rule. B<Defaults to:>
C<Parameter $name cannot be longer than $max characters> where C<$max> is the C<max> rule's
value.

=head4 C<min_error>

    min_error => 'Too short :(',

This is the error for C<min> rule. B<Defaults to:>
C<Parameter $name must be at least $rule->{min} characters long>

=head4 C<code_error>

    code_error => 'No likey 0_o',

This is the error for C<code> rule. B<Defaults to:>
C<Parameter $name contains incorrect data>

=head4 C<valid_values_error>

    valid_values_error => 'Pick the correct one!!!',

This is the error for C<valid_values> rule. B<Defaults to:>
C<Parameter $name must be $list_of_values> where C<$list_of_values> is the list of the
values you specified in the arrayref given to C<valid_values> rule joined by commas and
the last element joined by word "or".

=head1 AUTHOR

'Zoffix, C<< <'zoffix at cpan.org'> >>
(L<http://zoffix.com/>, L<http://haslayout.net/>, L<http://zofdesign.com/>)

=head1 BUGS

Please report any bugs or feature requests to C<bug-app-zofcms-plugin-formchecker at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=App-ZofCMS-Plugin-FormChecker>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc App::ZofCMS::Plugin::FormChecker

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-ZofCMS-Plugin-FormChecker>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/App-ZofCMS-Plugin-FormChecker>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/App-ZofCMS-Plugin-FormChecker>

=item * Search CPAN

L<http://search.cpan.org/dist/App-ZofCMS-Plugin-FormChecker>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2008 'Zoffix, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

