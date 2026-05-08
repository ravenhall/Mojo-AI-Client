# Mojo::AI::Client

A clean, modern Perl client for the **xAI Grok API** built with **Moo** + **Mojolicious**.

## Features

- Streaming support
- Intelligent caching
- Mojolicious helper integration
- Clean Moo-based API
- Full chat web UI example

## Quick Start

```perl
use Mojo::AI::Client;

my $client = Mojo::AI::Client->new(api_key => $ENV{XAI_API_KEY});

print $client->ask("Hello Grok!");
```

## Web Demo

Run the included chat UI:

```bash
morbo script/xai-chat
```

Then visit http://localhost:3000

## License

MIT
