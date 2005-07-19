package Maypole::Plugin::Config::Apache;

use warnings;
use strict;

use Apache;
use Maypole::Config;
use NEXT;

our $VERSION = '0.11';

=head1 NAME

Maypole::Plugin::Config::Apache - read config settings from httpd.conf

=head1 SYNOPSIS

    use Maypole::Application qw( Config::Apache -Setup );
    
    
    # in httpd.conf
    
    PerlSetVar MaypoleApplicationName "The Beer Database"
    PerlSetVar MaypoleUriBase         /beerdb
    PerlSetVar MaypoleTemplateRoot    /home/beerdb/www/beerdb/htdocs
    PerlSetVar MaypoleRowsPerPage     10
    
    PerlSetVar MaypoleDsn             "dbi:mysql:BeerDB"
    PerlSetVar MaypoleUser            username
    PerlSetVar MaypolePass            password
    
    # set a listref
    PerlAddVar MaypoleDisplayTables  beer 
    PerlAddVar MaypoleDisplayTables  brewery 
    PerlAddVar MaypoleDisplayTables  pub 
    PerlAddVar MaypoleDisplayTables  style
    
    # set a hashref
    PerlAddVar MaypoleMasonx "data_dir   => '/home/beerdb/www/beerdb/mdata'"
    PerlAddVar MaypoleMasonx "in_package => 'BeerDB::TestApp'"
    PerlAddVar MaypoleMasonx "comp_root => [ [ factory => '/usr/local/www/maypole/factory' ] ]"
    
    # set something from Perl code
    PerlSetVar MaypoleEvalFlooberiser "[ [ foo => 'bar', baz => { bee => 'boo } ] ]"
    
    # get lazy with lists
    PerlSetVar MaypoleEvalDisplayTables "[ qw( beer brewery pub style ) ]"
    

=head1 DESCRIPTION

Anything starting with C<Maypole> or C<MaypoleEval> is taken to be a config setting for Maypole. 
Everything after the C<Maypole> or C<MaypoleEval> is the variable name, in StudlyCaps form. 

Values from C<MaypoleEval> variables are run through an C<eval>, allowing arbitrarily complex 
data structures to be set, including coderefs, if anything needed that. 

Any value from a C<PerlAddVar> that contains a C<< => >> symbol is also run through an eval, so any valid perl expression for a hash value can be used.

Put C<Config::Apache> at the front of the Maypole::Application call, so that later plugins 
have access to the configuration settings. If your httpd.conf contains all of your Maypole 
settings, you can add the C<-Setup> flag, which calls C<< __PACKAGE__->setup >> for you. 

=head1 METHODS

=over 4

=item setup

=back

=cut

sub setup
{
    my $r = shift;
    
    # an Apache::Table object
    my $apache_cfg = Apache->server->dir_config;
    
    my $config = {};
    
    foreach my $k ( grep { /^Maypole/ } keys %$apache_cfg )
    {
        my @v = $apache_cfg->get( $k );
        
        # change from MaypoleVarName into var_name - stolen from HTML::Mason::ApacheHandler::studly_form()
        my $new_k = $k;
        $new_k =~ s/^Maypole//;
        $new_k =~ s/(^|.)([A-Z])/$1 ? "$1\L_$2" : "\L$2"/ge; 
        
        if ( $k =~ /^MaypoleEval/ )
        {
            $config->{ $new_k } = eval $v[0];
            die "Error constructing config value for $k from code: $@" if $@;       
        }
        else
        {
            $config->{ $new_k } = @v > 1 ? _fixup_addvar( $k, @v ) : $v[0];
        }
    }
    
    if ( $r->debug )
    {
        Data::Dumper->require || die "Failed to load Data::Dumper for debug output: $@";
        warn "Maypole config from Apache config file: " . Data::Dumper::Dumper( $config );
    }
    
    Maypole::Config->mk_accessors( keys %$config );
    
    $r->config( Maypole::Config->new( $config ) );
    
    $r->NEXT::DISTINCT::setup(@_);
}    
    
sub _fixup_addvar
{
    my ( $k, @v ) = @_;
    
    my @array = grep { ! /=>/ } @v;
    
    return \@array if @array == @v;
    
    die "'=>' present in some but not all values of $k" if @array;

    # rather than parsing the value, just run it through a string eval, so anything 
    # that would work in Perl, can go in the     
    my @err;
    my %hash = map { my @each = eval $_; push( @err, $@ ) if $@; @each } @v;
    
    die "Error constructing hash for config entry $k", @err if @err;
    
    return \%hash;
} 

=head1 EXAMPLE

With all the config moved to C<httpd.conf>, the actual driver is reduced to a few lines of code. 
Why not inline that in C<httpd.conf> too? 

    <VirtualHost xxx.xxx.xx.xx>
        
        ServerName beerdb.riverside-cms.co.uk
        ServerAdmin cpan@riverside-cms.co.uk
    
        DocumentRoot /home/beerdb/www/beerdb/htdocs
        
        #
        # Set up Maypole via Maypole::Plugin::Config::Apache
        #
        PerlSetVar MaypoleApplicationName "The Beer Database"
        PerlSetVar MaypoleUriBase         /beerdb
        PerlSetVar MaypoleTemplateRoot    /home/beerdb/www/beerdb/htdocs
        PerlSetVar MaypoleRowsPerPage     10
        
        PerlSetVar MaypoleDsn             "dbi:mysql:BeerDB"
        PerlSetVar MaypoleUser            username
        PerlSetVar MaypolePass            password
        
        PerlAddVar MaypoleDisplayTables  beer 
        PerlAddVar MaypoleDisplayTables  brewery 
        PerlAddVar MaypoleDisplayTables  pub 
        PerlAddVar MaypoleDisplayTables  style
        
        PerlAddVar MaypoleMasonx "comp_root  => [ [ factory => '/usr/local/www/maypole/factory' ] ]"
        PerlAddVar MaypoleMasonx "data_dir   => '/home/beerdb/www/beerdb/mdata'"
        PerlAddVar MaypoleMasonx "in_package => 'BeerDB::TestApp'"
        
        PerlAddVar MaypoleRelationships     "a brewery produces beers"
        PerlAddVar MaypoleRelationships     "a style defines beers"
        PerlAddVar MaypoleRelationships     "a pub has beers on handpumps"
        
        <Directory /home/beerdb/www/beerdb/htdocs/>
            Allow from all
            AllowOverride none
            Order allow,deny
    
            <Perl>
            {
                package BeerDB;
                use Maypole::Application qw( Config::Apache MasonX AutoUntaint Relationship -Setup -Debug2 );
                BeerDB->auto_untaint;
                BeerDB->init;
            }
            </Perl>
            
            SetHandler perl-script
            PerlHandler BeerDB
        </Directory>
        
        CustomLog /home/beerdb/www/beerdb/logs/access.log combined env=log
        ErrorLog  /home/beerdb/www/beerdb/logs/error.log    
        
    </VirtualHost>

Watch out for the chicken and the egg. The C<Perl> section defining the C<BeerDB> package must 
come after all the Maypole config settings (or else the settings won't yet exist when BeerDB 
tries to read them), but before the C<PerlHandler BeerDB> directive (because the package needs 
to exist by then).
    
=head1 AUTHOR

David Baird, C<< <cpan@riverside-cms.co.uk> >>

=head1 BUGS

I think a hash with a single entry might not work, prod me if you need this. 

Won't work for config variables with capital letters in them. 

Please report any bugs or feature requests to
C<bug-maypole-plugin-config-apache@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Maypole-Plugin-Config-Apache>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2005 David Baird, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Maypole::Plugin::Config::Apache
