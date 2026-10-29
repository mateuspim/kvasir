# Contributing to Kvasir

Thanks for helping. Kvasir is a small project; issues and focused
pull requests are welcome. Results from hardware the project has not seen yet,
especially AMD cards, are as useful as code.

## Before you start

- Bugs and ideas: open an issue first for anything larger than a small fix.
- Security problems: follow [SECURITY.md](SECURITY.md), not a public issue.
- Read [AGENTS.md](AGENTS.md): it holds the rules for people and coding agents
  alike, and [docs/architecture.md](docs/architecture.md).

## Set up

```sh
git clone https://github.com/mateuspim/kvasir
cd kvasir
make env      # writes .env; then set STRATA_DATA_DIR
make key
make test
```

You do not need a GPU or a running docker daemon for `make test`. To run the
stack itself, follow the [Quick start](README.md#quick-start).

## Make a change

1. Branch from `master`.
2. Keep the change focused; update the README section or guide it affects.
3. Run `make test`. If you add a check, break what it guards and confirm it
   fails before trusting it.
4. Changed something that affects speed or memory? Include `make bench` and
   `make status` output, measured with the GPU otherwise idle, and your GPU,
   RAM and image tag.
5. Durable design choice? Add an ADR under [docs/adr](docs/adr/README.md).

## Commit style

Plain imperative subject ("Add …", "Keep …"), under ~72 characters, and a
body that explains why.

## Pull request checklist

- [ ] `make test` passes
- [ ] Docs and CHANGELOG (Unreleased) updated
- [ ] No personal paths, hostnames, addresses or keys in tracked files

## License

By contributing you agree your work is released under the [MIT License](LICENSE).
