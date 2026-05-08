package Mojo::AI::Client;
use Moo;
use MooX::Types::MooseLike::Base qw(Str Int);
use Mojo::UserAgent;
use Mojo::Cache;
use Mojo::JSON qw(encode_json);
use Digest::SHA qw(sha256_hex);
use namespace::clean;

# Attributes
has api_key => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has default_model => (
    is      => 'ro',
    isa     => Str,
    default => 'grok-4.3',
);

has ua => (
    is      => 'lazy',
    isa     => sub { $_[0]->isa('Mojo::UserAgent') },
    default => sub { Mojo::UserAgent->new->max_redirects(5) },
);

has cache => (
    is      => 'lazy',
    isa     => sub { $_[0]->isa('Mojo::Cache') },
    default => sub { Mojo::Cache->new(max_keys => 500) },
);

has cache_ttl => (
    is      => 'ro',
    isa     => Int,
    default => 3600,
);

# ==================== INTERNAL ====================

sub _cache_key {
    my ($self, $messages, $opts) = @_;
    my $data = { messages => $messages, %$opts{qw(model temperature)} };
    return 'mojoai:' . sha256_hex(encode_json($data));
}

sub _raw_request {
    my ($self, $messages, %opts) = @_;

    my $use_cache = !$opts{stream} && ($opts{temperature} // 0.7) < 0.3;

    if ($use_cache) {
        my $key = $self->_cache_key($messages, \%opts);
        if (my $cached = $self->cache->get($key)) {
            return $cached;
        }
    }

    my $tx = $self->ua->post(
        'https://api.x.ai/v1/chat/completions' => {
            Authorization  => 'Bearer ' . $self->api_key,
            'Content-Type' => 'application/json',
        } => json => {
            model       => $opts{model}       // $self->default_model,
            messages    => $messages,
            temperature => $opts{temperature} // 0.7,
            max_tokens  => $opts{max_tokens}  // 2048,
            stream      => $opts{stream}      // \0,
            %{$opts{extra} // {}},
        }
    );

    my $res = $tx->result or die "Request failed: " . $tx->error->{message};

    unless ($res->is_success) {
        my $err = $res->json // {};
        die "xAI API Error (" . $res->code . "): " . ($err->{error}{message} // $res->body);
    }

    my $data = $res->json;

    if ($use_cache) {
        $self->cache->set($self->_cache_key($messages, \%opts), $data, $self->cache_ttl);
    }

    return $data;
}

# ==================== PUBLIC API ====================

sub ask {
    my ($self, $prompt, %opts) = @_;
    my $messages = $opts{messages} // [{ role => 'user', content => $prompt }];
    my $data = $self->_raw_request($messages, %opts);
    return $self->extract_text($data);
}

sub ask_with_system {
    my ($self, $system, $user, %opts) = @_;
    my $messages = [
        { role => 'system', content => $system },
        { role => 'user',   content => $user },
    ];
    return $self->ask($user, messages => $messages, %opts);
}

sub ask_full {
    my ($self, $messages, %opts) = @_;
    return $self->_raw_request($messages, %opts);
}

sub stream {
    my ($self, $prompt, $callback, %opts) = @_;

    my $messages = $opts{messages} // [{ role => 'user', content => $prompt }];

    $self->ua->post(
        'https://api.x.ai/v1/chat/completions' => {
            Authorization  => 'Bearer ' . $self->api_key,
            'Content-Type' => 'application/json',
        } => json => {
            model       => $opts{model}       // $self->default_model,
            messages    => $messages,
            temperature => $opts{temperature} // 0.75,
            max_tokens  => $opts{max_tokens}  // 2048,
            stream      => \1,
        } => sub ($ua, $tx) {
            my $res = $tx->result;
            if ($res && $res->is_success) {
                $res->content->on(read => sub ($content, $bytes) {
                    for my $line (split /\n/, $bytes) {
                        next unless $line =~ /^data: /;
                        next if $line eq 'data: [DONE]';
                        my $json = substr($line, 6);
                        my $data = eval { Mojo::JSON::decode_json($json) };
                        next unless $data && $data->{choices};
                        my $chunk = $data->{choices}[0]{delta}{content} // '';
                        $callback->($chunk, $data) if length $chunk;
                    }
                });
            } else {
                $callback->(undef, { error => 'Stream failed' });
            }
        }
    );
}

sub extract_text  { $_[1]{choices}[0]{message}{content} // '' }
sub extract_usage { $_[1]{usage} // {} }
sub clear_cache   { $_[0]->cache->flush }

sub register_mojo_helper {
    my ($self, $app) = @_;
    $app->helper(xai => sub { $self });
}

1;
