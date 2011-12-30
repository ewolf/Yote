package SE::FlavorEditor;

use strict;

use base 'UTIL::UI';

sub new {
    my $pkg = shift;
    my $class = ref( $pkg ) || $pkg;
    my $self = {};
    return bless $self, $class;
}

sub edit_flavor {
    my( $self, $flav, $form, $acct ) = @_;

    $self->check_updates( $form );
    $self->print_html_open( "Editing Flavor ".$flav->get_name(), $acct );

    print $self->href( "?session=$form->{session}", 'back to lobby' );
    print '<BR><BR>Flavor Name : ',$self->upfield( $flav, 'name' )."<BR>";

    print "<hr>";
    print '<h3>Default Values</h3>';
    $self->alt_table( 
		      [ 'Number of Players',$self->upfield( $flav, 'number_players' ) ],
		      [ 'Starting Player Resources',$self->upfield( $flav, 'starting_resources' ) ],
		      [ 'Starting Player Tech Level', $self->upfield( $flav, 'starting_tech_level' ) ],
		      [ 'Starting Number of Sectors', $self->upfield( $flav, 'starting_sectors' ) ],
		      [ 'Turns are run',$self->upsel( $flav, 'turns_run', ['every night','after all players are ready'], ['every_night','when_ready'] ) ],
		      );
    
    print '<hr>';
    print '<h3>Ships</h3>';
    my $prots = $flav->get_prototypes();
    if( $form->{add_row} ) {
        my $nextid = 1 + scalar( keys %$prots );
        my $newrow = new G::Base();
        $newrow->set_design_id( $nextid );
        $newrow->set_name( 'new entry' ); 
        $prots->{$nextid} = $newrow;
    }
    
    my @items = sort { $a->get_tech_level() <=> $b->get_tech_level() || 
			      lc($a->get_name()) cmp lc($b->get_name()) } values %$prots;
    my( @titles ) = qw/name tech_level size cost defense attack_beams targets jumps damage_control racksize self_destruct type /;

    print $self->href( "?session=$form->{session}&class=$form->{class}&edit_flavor=$form->{edit_flavor}&add_row=1", "add entry" )."<BR><BR>";
    $self->table( @titles, 'action' );
    for my $item (@items) {
        $self->row( (map { $self->upfield( $item, $_, 'size='.($_=~/name|type/?'10':'3') ) } @titles), $self->href( "javascript:void(0)", 'delete', qq~onclick='if(confirm("Really Delete?")){ window.location="?session=$form->{session}&class=$form->{class}&edit_flavor=$form->{edit_flavor}&delete=$item->{ID}", "delete"}'~ ) );
    }
    print '</table>';

    print qq~<input type=hidden name="session" value="$form->{session}">~;
    print qq~<input type=hidden name="class" value="$form->{class}">~;
    print qq~<input type=hidden name="edit_flavor" value="$form->{edit_flavor}">~;

    print "<P><input type=submit value=Update>";
    $self->print_html_close();
} #edit_flavor

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
