use Coro;
use Data::Dumper;
my $loofa;

sub make {
    my $name = shift;
    async {
        print STDERR Data::Dumper->Dump([$coro::current]);
        while( 1 ) {
            print STDERR ">$name ($Coro::current) $loofa $$\n";
            $loofa++;
            cede;
#            sleep 1;
        }
    }
};

make( "Juan" );
make( "Tuna" );
make( "Reah" );

    Coro::schedule;

1;
