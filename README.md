# FileBlink

## The Problem

You are working with files that have a clear relationship based on their file extensions and would like to switch
quickly between files that have a similar filename root (e.g. `foo.h` and `foo.c`) even if they are in differnt places in
the directory tree (e.g. `a/include/b/c/foo.h` vs `a/src/c/foo.c`).

## The Solution

Recursively search from the directory of the current file in Neovim (e.g. `foo.h`) upwards in the directory tree, and
then downwards, until a file with a matching mapped extension exists (e.g. `foo.c`). Also, make it fast by caching the
location of the found file, and the directory structure -- making future lookups of similar files fast (e.g.
`a/include/b/c/bar.h` to `a/src/c/bar.c` will not require crawling the tree). Prevent the search from going above any
detected project root, as defined by the directory containing files normally found in a project root directory.

## Installation

- Neovim required
- Install using your favorite plugin manager (e.g. (lazy.nvim)[https://lazy.folke.io/usage]).
```
{
   'samr/fileblink.nvim',
    config = function()
      require("fileblink").setup(
        -- Customize extension mappings
        extension_maps = {
            -- Add your own mappings here, for example:
            py = { "pyi", "pyx" },
            pyi = { "py" },
            pyx = { "py" },
        },

        -- Customize root markers
        root_markers = { ".git", "package.json", "Cargo.toml" },

        -- Adjust cache size (i.e. number of files and directories to store, default=10000)
        cache_size = 500,
      )
    end,
}
```

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
```

Note that if you override a specific setting (e.g. `extension_maps`) that it will be entirely replace and not added-to.
So be explicit in what you want. However, if you overwrite only `extension_maps` then the above defulat `root_markers`
will still be defined as the default specified above.

## Default Commands

The default commands available are:

- `:FileBlinkSwitch` - Switch to the first available related file
- `:FileBlinkShowFiles` - List all available files for current basename
- `:FileBlinkClearCache` - Clear the cache
- `:FileBlinkShowStats` - Show cache usage statistics

To map themp to keys you can use something like the following.

```
vim.keymap.set('n', '<leader>fs', '<cmd>FileBlinkSwitch<cr>', { desc = 'Switch to related file' })
vim.keymap.set('n', '<leader>fa', '<cmd>FileBlinkShowFiles<cr>', { desc = 'Show available files' })
```

However, these mappings are not provided by default.


## Thanks

The following plugins provide similar functionality and were an inspiration for this one:

- [tpope/vim-projectionist](https://github.com/tpope/vim-projectionist)
- [jakemason/ouroboros](https://github.com/jakemason/ouroboros.nvim)
