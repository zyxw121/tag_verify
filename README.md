# Tag Verify
A darktable plugin for imposing tag constraints.

## Install:

1. Compile the lpeg module. The source may be found [here](http://www.inf.puc-rio.br/~roberto/lpeg/). Move the produced `lpeg.so` file into `tag_verify`.

2. Optionally run tests with `lua test.lua` (requires the [lust](https://github.com/bjornbytes/lust) module)

3. Identify your darktable config directory: [config]. This may be either `$HOME/.config/darktable`, or (if you have installed darktable via flatpack) `$HOME/.var/app/org.darktable.Darktable/config/darktable`.


4. Move the `tag_verify` directory (or at least the three files `tag_verify.lua`, and `parse.lua`, and `lpeg.so`) to `[config]/lua/tag_verify`.

5. Add the following lines to your `[config]/luarc` file

```
package.cpath = "[config]/lua/tag_verify/lpeg.so;" .. package.cpath
require "tag_verify/tag_verify"
```

