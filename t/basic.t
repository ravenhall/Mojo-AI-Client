use Test::More;
use Mojo::AI::Client;

my $client = Mojo::AI::Client->new(
    api_key => 'dummy-key-for-testing'
);

ok( defined $client, 'Client object created' );
ok( $client->can('ask'), 'has ask method' );
ok( $client->can('stream'), 'has stream method' );

done_testing();