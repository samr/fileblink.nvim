# FileBlink

## The Problem

You are working with files that have a clear relationship based on their file extensions and would like to switch
quickly between files that have a similar filename root (e.g. `foo.h` and `foo.c`) even if they are in different places
in the directory tree (e.g. `a/include/b/c/foo.h` vs `a/src/c/foo.c`).

## The Solution

- Recursively search from the directory of the current file in Neovim (e.g. `foo.h`) upwards in the directory tree, and
    then downwards, until a file with a matching mapped extension exists (e.g. `foo.c`).
- Make it fast by caching the location of the found file, and the directory structure. This should make future lookups
    of similar files fast (e.g. `a/include/b/c/bar.h` to `a/src/c/bar.c` will not require crawling the tree).
- Prevent searching for anything above a detected project root directory. The project root is detected by finding one of
    a set of special files or directories that only exist in the root (e.g. a '.git' directory).
- Provide a switch based on file extension, listed in priority order.
- Provide an alternative switch based on prefix and/or suffix, but assuming the same extension.

## Installation

- Neovim required
- Install using your favorite plugin manager (e.g. [lazy.nvim](https://lazy.folke.io/usage)).
- Optionally configure your own global settings:
```
{
   'samr/fileblink.nvim',
    config = function()
      require("fileblink").setup({
        -- Add your own extension mappings here, for example:
        extension_maps = {
            h = { "cpp", "cc", "c" },
            hpp = { "cpp", "cc" },
            c = { "h" },
            cc = { "hpp", "h" },
            cpp = { "hpp", "h" },
        },

        -- Add your own alternative mappings here, for example:
        alternative_patterns = {
            ["_test"] = { "" },       -- suffix  (foo_test.cc -> foo.cc)
            ["test_/"] = { "" },      -- prefix  (test_foo.cc -> foo.cc)
            ["test_/_spec"] = { "" }, -- prefix + suffix  (test_foo_spec.cc -> foo.cc)
            [""] = { "_test", "test_/", "test_/_spec" },  -- maps back (foo.cc -> *)
        },

        -- Set project root markers (i.e. files or directories that exist only in project root).
        root_markers = { ".git", "package.json" },

        -- Adjust cache size (i.e. number of files and directories to store, default=10000)
        cache_size = 500,
    })
    end,
}
```

## Per-project Configuration

Creating a `.fileblinkrc` file in the project root directory allows overriding global configuration settings. The file
uses the same syntax as the lua configuration. An example of what the file might look like is as follows.

```
# This is a .fileblinkrc file
cache_size = 5000

extension_maps = {
    h = { "cpp", "cc", "c" },
    hpp = { "cpp", "cc" },
    c = { "h" },
    cc = { "hpp", "h" },
    cpp = { "hpp", "h" },
}

alternative_patterns = {
    ["_test"] = { "" },
    ["test_/"] = { "" },
    ["test_/_spec"] = { "" },
    [""] = { "_test", "test_/", "test_/_spec" },
}
```

The `.fileblinkrc` file will be auto loaded when changing buffers or creating new ones. The autoloading can be turned
off with `autoload_fileblinkrc = false`, in which case it will only be loaded once on Neovim start based on the current
working directory. Loading of `.fileblinkrc` files can be turned off altogether by setting `ignore_fileblinkrc = true`.

## Default Commands

The default commands available are:

- `:FileBlinkSwitch` - Switch to the first available related file
- `:FileBlinkSwitchAlternative` - Switch to the first available related file based on suffix mapping
- `:FileBlinkShowFiles` - List all available files for current basename
- `:FileBlinkShowFilesAlternative` - List all available alternative files for current basename
- `:FileBlinkClearCache` - Clear the cache
- `:FileBlinkShowStats` - Show cache usage statistics
- `:FileBlinkShowConfig` - Attempt to show the current configuration
- `:FileBlinkLoadConfig` - Attempt to load or reload any .fileblinkrc config file found (will not exist when `ignore_fileblinkrc` is true)

To map them to keys you can use something like the following.

```
vim.keymap.set('n', '<leader>fs', '<cmd>FileBlinkSwitch<cr>', { desc = 'Switch to related file' })
vim.keymap.set('n', '<leader>fa', '<cmd>FileBlinkShowFiles<cr>', { desc = 'Show available files' })
```

However, these mappings are not provided by default.


## Default Configuration

The default configuration settings are:
```
    -- Extension mappings: source extension -> list of target extensions
    extension_maps = {
        -- C/C++
        c = { "h", "hpp", "hxx" },
        cc = { "h", "hpp", "hxx" },
        cpp = { "h", "hpp", "hxx" },
        cxx = { "h", "hpp", "hxx" },
        cu = { "cuh" },

        h = { "c", "cc", "cpp", "cxx" },
        hpp = { "c", "cc", "cpp", "cxx" },
        hxx = { "c", "cc", "cpp", "cxx" },
        cuh = { "cu" },

        -- JavaScript/TypeScript
        js = { "ts", "jsx", "tsx" },
        ts = { "js", "jsx", "tsx" },
        jsx = { "js", "ts", "tsx" },
        tsx = { "js", "ts", "jsx" },

        -- Python
        py = { "pyi", "pyx" },
        pyi = { "py" },
        pyx = { "py" },

        -- Web files
        html = { "css", "js", "ts" },
        css = { "html", "scss", "sass" },
        scss = { "css", "html" },
        sass = { "css", "html" },
    },

    -- Alternative file patterns: prefix/suffix -> list of possible prefix/suffixes
    alternative_patterns = {
        -- Test file patterns
        ["_test"] = { "" },       
        ["test_/"] = { "" },      
        ["_spec"] = { "" },
        [".test"] = { "" },
        [".spec"] = { "" },

        -- Implementation patterns
        ["_impl"] = { "" },
        ["_implementation"] = { "" },
        [".impl"] = { "" },

        -- Mock patterns
        ["_mock"] = { "" },
        [".mock"] = { "" },

        -- Collected mapping the other way.
        [""] = {
            "_test",
            "test_/",
            "_spec",
            ".test",
            ".spec",
            "_impl",
            "_implementation",
            ".impl",
            "_mock",
            ".mock",
        },
    },

    -- Root directory marker files (plugin won't search above directories containing these)
    root_markers = {
        ".git",
        ".svn",
        ".hg",
        ".idea",
        ".vscode",
        "Makefile",
        "CMakeLists.txt",
        "Cargo.toml",
        "package.json",
        "LICENSE",
        "LICENSE.md",
    },

    -- Maximum depth to search upward from current file
    max_search_depth = 10,

    -- Cache settings
    cache_enabled = true,
    cache_size = 10000,

    -- Whether to ignore .fileblinkrc files, when true will not autoload or parse them.
    ignore_fileblinkrc = false,

    -- Whether to autoload the file based on the buffer. When false, it will only load once on startup based on the
    -- current working directory.
    autoload_fileblinkrc = true,
```

Note that if you override a specific default setting, it will entirely replace the value rather than doing a merge of
what was there. For example, when loading the above example `.fileblinkrc` file, it will replace the default
`extension_maps` value such that there is no mapping for going between "html" and "js" files. However, a merge is done
across all the settings such that, in that example, the `cache_size` will remain 10000, since it was not overridden or
specified explicitly.

## Thanks

The following plugins provide similar functionality and were an inspiration for this one:

- [tpope/vim-projectionist](https://github.com/tpope/vim-projectionist)
- [jakemason/ouroboros](https://github.com/jakemason/ouroboros.nvim)
