package Yote::Sample::SimpleTodo;

use strict;

use base "Yote::AppRoot";

sub _init_account {  
  my( $self, $account ) = @_;

  my $first_todo_item = "Enter todo items";
  $account->add_to_my_todos( $first_todo_item ); 
  $account->set_current_todo( $first_todo_item ); 
}

sub add_item {
  my( $self, $data, $account, $environ ) = @_;

  $account->add_once_to_my_todos( $data );
}

sub pick_random_todo {
  my( $self, $data, $account, $environ ) = @_;
  
  my $todos = $account->get_my_todos();
  my $rand = $todos->[ rand( @$todos ) ];
  $self->set_current_todo( $rand );
  return $rand;
}

sub complete_current_item {
  my( $self, $data, $account, $environ ) = @_;

  my $current = $account->get_current_todo();
  $account->remove_from_my_todos( $current );

  return $self->pick_random_todo( $data, $account, $environ );
}

1;

__END__

=head1 NAME

Yote::Sample::SimpleToDo

=head1 DESCRIPTION 

A simple to do list that serves up one thing to do at a time

=head1 PUBLIC API METHODS

=over 4

=item add_item

=item pick_random_todo

=item complete_current_item

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
