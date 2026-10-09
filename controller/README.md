# EasyNet Controller scaffold

This development-only Go stub has no deployment, SSH, VPN, vault, configuration,
or network operations. Its only supported command is `--version`; invalid
arguments print fixed usage and return status 2.

With the pinned Go 1.27.2 toolchain, run the offline unit and formatting checks:

```sh
make -C controller check
```

Override `GO`, `GOFMT`, `GOCACHE`, and `GOPATH` with make assignments when using
the repository's pinned toolchain and isolated caches. The test fixtures cover
only this development stub. They do not define a product schema or acceptance
for operational capabilities.

This scaffold does not satisfy product acceptance. Later stages must pass their
reviewed implementation and acceptance gates before operational capabilities
are considered.
