#!/usr/bin/env perl
package GServer;
use lib $ENV{GLIB} || '../../..';
use G::ARCADE::StellarExpanse::IO;
use Data::Dumper;
use HTTP::Server::Simple::CGI;
use base qw(HTTP::Server::Simple::CGI);
use JSON qw(to_json);
use strict;
use warnings;

my $shutdown = 0;

my $vs = 0; #server verbose

my $basepath = "$ENV{GLIB}/G" || "../";

# Get port and backgrounding (if this needs to be
# more complicated -- more options, start using real
# module)
my $port = 8000;
my $background = 0;
if (scalar @ARGV) {
  my $port_pos = 0;
  if ($ARGV[0] eq "-d")
  {
    $background = 1;
    $port_pos++;
  }
  if ($port_pos < scalar @ARGV)
  {
    $port = $ARGV[$port_pos];
    if ($port !~ /^\d+$/) {
      print "Usage: serv.pl [-d] [port]\n";
      exit;
    }
  }
}

sub restart {
  my ($self) = @_;
  
  if ($shutdown)
  {
    # Code to run on shutdown
      print STDERR "Saving Cache\n";
      G::Base::save_all();
      print STDERR "Done\n";
    exit;
  }
  else
  {
    # Place any restart behavior here
    $self->SUPER::restart(@_);
  }
}

sub shutdown_gracefully {
  $shutdown = 1;
  $HTTP::Server::Simple::SERVER_SHOULD_RUN = 0;
}

sub g_request
{
  eval {
    my ($CGI) = @_;
    print "HTTP/1.0 200 OK\r\n";
    print $CGI->header(-charset=>'utf8', -content_type=>'text/json');
#    print $CGI->header(-content_type=>'text/json');
#    print "Content-Type: text/json\r\n";
#    print "Server: us\r\n";
#    print "Date: ".scalar(localtime)."\r\n";
#    print "Connection: close\r\n";

    my $form = $CGI->Vars;
    print STDERR "incoming request : ".join(',',map { "$_=[$form->{$_}]" } keys %$form )."\n" if $vs;

    my $resp = to_json( G::ARCADE::StellarExpanse::IO::process_data( $form ) );
#    print "Content-Length: ". (2 + length($resp))."\r\n\r\n";
    print "(";
    print $resp;
    print STDERR "Response with: $resp\n\n" if $vs;
  };
  if( $@ ) {
      G::Base::save_all();
    print to_json( { err => $@ } );
    print STDERR "ERR : Response with: ".to_json({err => $@})."\n\n";
    print STDERR Data::Dumper->Dump( [$@] );
  }
  print ")";
}

sub file
{
    my ($CGI) = @_;
    print STDERR "Request for ".$CGI->path_info."\n" if $vs;
    print "HTTP/1.0 200 OK\r\n";
    if ($CGI->path_info =~ /\.html?$/)
    {
      print $CGI->header(-charset=>'utf8', -content_type=>'text/html');
    }
    elsif ($CGI->path_info =~ /\.png$/) 
    {
      print $CGI->header(-content_type=>'image/png');      
    }
    open(R, $basepath . $CGI->path_info) || die "no file";
    while (<R>) { print $_; }
    close(R);
}


# Dispatch tree
# Assumes static dispatch by uri path part
my %dispatch = (
  '/' => \&g_request,
);

# Handle the request, dispatch to appropriate 
# function in dispatch tree or return error 
# Note: handler functions are expected to return
# the entire data for response including status.
sub handle_request {
  my ($self, $cgi) = @_;

  if ($cgi->cgi_error)
  {
    print $cgi->header(-status=>$cgi->cgi_error);
    return;
  } 

  my $path = $cgi->path_info();
  my $handler = $dispatch{$path}; 

  if (ref($handler) ne "CODE")
  {
    $handler = \&file;
  }

  # Do any per-request (even for failure) handling here

  if (ref($handler) eq "CODE") {
    # Do any generic pre-handler per-request (for real page) handling here
    eval {
      $handler->($cgi);
    };
    my $saved_result = $@;
    # Do any generic post-handler per-request (for real page) handling here
#    print STDERR "saved_result: $@\n";

    #Note: this is a bit lame - we should probably grab the output 
    #into an object or something so that we don't have partial 
    #writing and then the error
    if ($saved_result)
    {
      print "HTTP/1.0 500 Internal Server Error\r\n";
      print $cgi->header( -charset=>'utf8'),
            $cgi->start_html('Error'),
            $cgi->h1('Internal Server Error'),
            $cgi->pre($saved_result),
            $cgi->end_html;
    }

  } else {
    print "HTTP/1.0 404 Not found\r\n";
    print $cgi->header,
          $cgi->start_html('Not found'),
          $cgi->h1('Not found'),
          $cgi->end_html;
  }
}

# setup SIGTERM/SIGINT/SIGQUIT handlers to shut down gracefully
$SIG{TERM} = $SIG{INT} = $SIG{QUIT} = \&shutdown_gracefully;

# start the server
my $gs = GServer->new($port);
if ($background)
{
  my $pid = $gs->background();
  print "Server is running in the background on pid $pid\n";
}
else
{
  $gs->run();
}

1;
