package Yote;

use vars qw($VERSION);
$VERSION = '0.092';

1;

__END__

=head1 NAME

Yote - Code server side, use client side.

=head1 SYNOPSIS

Yote is a platform that 

=over 4

* serves up any number of separate applications

* provides account management 

* provides access control for objects and methods

=back

Yote on the server side is a server that is a

=over 4

* schemaless object database with a recursive tree structure

* multi-threaded request queuing server 

* single-threaded execution server

=back

Yote on the client is a javascript library that provides

=over 4

* RPC bound yote objects

* web controls that bind to the yote objects

* web controls for account management

=back

=head1 DESCRIPTION

I wrote Yote because I wanted to write object oriented applications, 
particulally web applications and prototypes, in a ferenic ADHD style.

I wanted the objects and their data to connect together as 
easily as one connects tinker toys together.
I found writing and modifying table schemas, especially for prototypes, is a
drag on the development and testing and I wanted to get rid of that 
step once and for all for at least prototype development. 

I had chance to use SOAP and XMLHttpdRequest calls. SOAP I found too
slow, and at the time had seen it only for php, jsp and other server
side web languages. 


=cut
