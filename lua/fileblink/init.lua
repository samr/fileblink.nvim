local M = {}

-----------------
-- Default config
--
local default_config = {
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
        ["_test"] = { "" }, -- suffix
        ["test_/"] = { "" }, -- prefix
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
}

---------------
-- Plugin state
--
local config = {}
local file_cache = {}
local cache_order = {}
local directory_mapping_cache = {}
local dir_cache_order = {}

--------------------
-- Utility functions
--
local function get_file_parts(filepath)
    local basename = vim.fn.fnamemodify(filepath, ":t:r")
    local extension = vim.fn.fnamemodify(filepath, ":e")
    local directory = vim.fn.fnamemodify(filepath, ":h")
    return basename, extension, directory
end

local function find_root_directory(start_dir)
    local current_dir = start_dir
    local depth = 0

    while depth < config.max_search_depth do
        -- Check if current directory contains any root markers
        for _, marker in ipairs(config.root_markers) do
            local marker_path = current_dir .. "/" .. marker
            if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
                return current_dir
            end
        end

        -- Move up one directory
        local parent_dir = vim.fn.fnamemodify(current_dir, ":h")
        if parent_dir == current_dir then
            -- Reached filesystem root
            break
        end

        current_dir = parent_dir
        depth = depth + 1
    end

    return start_dir -- Return original directory if no root found
end

local function get_cache_key(basename, extension, root_dir)
    return root_dir .. ":" .. basename .. "." .. extension
end

local function add_to_cache(key, filepath)
    if not config.cache_enabled then
        return
    end

    -- Remove if already exists to update order
    for i, cached_key in ipairs(cache_order) do
        if cached_key == key then
            table.remove(cache_order, i)
            break
        end
    end

    -- Add to front of cache
    table.insert(cache_order, 1, key)
    file_cache[key] = filepath

    -- Maintain cache size limit
    while #cache_order > config.cache_size do
        local old_key = table.remove(cache_order)
        file_cache[old_key] = nil
    end
end

local function get_directory_mapping_key(source_dir, source_ext, target_ext, root_dir)
    local relative_source = vim.fn.fnamemodify(source_dir, ":p"):gsub("^" .. vim.fn.fnamemodify(root_dir, ":p"), "")
    return root_dir .. ":" .. relative_source .. ":" .. source_ext .. "->" .. target_ext
end

local function add_directory_mapping_to_cache(source_dir, source_ext, target_dir, target_ext, root_dir)
    if not config.cache_enabled then
        return
    end

    local key = get_directory_mapping_key(source_dir, source_ext, target_ext, root_dir)
    local relative_target = vim.fn.fnamemodify(target_dir, ":p"):gsub("^" .. vim.fn.fnamemodify(root_dir, ":p"), "")

    -- Remove if already exists to update order
    for i, cached_key in ipairs(dir_cache_order) do
        if cached_key == key then
            table.remove(dir_cache_order, i)
            break
        end
    end

    -- Add to front of cache
    table.insert(dir_cache_order, 1, key)
    directory_mapping_cache[key] = relative_target

    -- Maintain cache size limit
    while #dir_cache_order > config.cache_size do
        local old_key = table.remove(dir_cache_order)
        directory_mapping_cache[old_key] = nil
    end
end

local function get_from_cache(key)
    if not config.cache_enabled then
        return nil
    end

    local cached_path = file_cache[key]
    if cached_path and vim.fn.filereadable(cached_path) == 1 then
        -- Move to front of cache (LRU)
        for i, cached_key in ipairs(cache_order) do
            if cached_key == key then
                table.remove(cache_order, i)
                table.insert(cache_order, 1, key)
                break
            end
        end
        return cached_path
    end

    -- Remove invalid cache entry
    if cached_path then
        file_cache[key] = nil
        for i, cached_key in ipairs(cache_order) do
            if cached_key == key then
                table.remove(cache_order, i)
                break
            end
        end
    end

    return nil
end

local function get_predicted_directory(source_dir, source_ext, target_ext, root_dir)
    if not config.cache_enabled then
        return nil
    end

    local key = get_directory_mapping_key(source_dir, source_ext, target_ext, root_dir)
    local cached_relative_dir = directory_mapping_cache[key]

    if cached_relative_dir then
        -- Move to front of cache (LRU)
        for i, cached_key in ipairs(dir_cache_order) do
            if cached_key == key then
                table.remove(dir_cache_order, i)
                table.insert(dir_cache_order, 1, key)
                break
            end
        end

        -- Convert relative path back to absolute
        local predicted_dir = vim.fn.fnamemodify(root_dir, ":p") .. cached_relative_dir
        predicted_dir = vim.fn.fnamemodify(predicted_dir, ":p:h") -- Normalize path

        -- Verify directory exists
        if vim.fn.isdirectory(predicted_dir) == 1 then
            return predicted_dir
        else
            -- Remove invalid cache entry
            directory_mapping_cache[key] = nil
            for i, cached_key in ipairs(dir_cache_order) do
                if cached_key == key then
                    table.remove(dir_cache_order, i)
                    break
                end
            end
        end
    end

    return nil
end

local function search_file_in_directory(directory, basename, extension)
    local filename = basename .. "." .. extension
    local filepath = directory .. "/" .. filename

    if vim.fn.filereadable(filepath) == 1 then
        return filepath
    end

    return nil
end

local function get_prefix_and_suffix(alternative_pattern)
    if alternative_pattern == nil or alternative_pattern == "" then
        return "", ""
    end
    local prefix, suffix = string.match(alternative_pattern, "([^/]*)/(.*)")
    if prefix ~= nil and suffix ~= nil then
        return prefix, suffix
    end
    prefix = string.match(alternative_pattern, "([^/]+)/")
    if prefix ~= nil then
        return prefix, ""
    end
    suffix = string.match(alternative_pattern, "/(.+)")
    if suffix ~= nil then
        return "", suffix
    end

    return "", alternative_pattern
end

local function get_basename_parts(basename)
    for pattern, _ in pairs(config.alternative_patterns) do
        prefix, suffix = get_prefix_and_suffix(pattern)
        local core_basename = basename
        if prefix ~= "" and vim.startswith(basename, prefix) then
            core_basename = core_basename:sub(#prefix + 1)
        end
        if suffix ~= "" and vim.endswith(basename, suffix) then
            core_basename = core_basename:sub(1, -(#suffix + 1))
        end
        if core_basename ~= basename then
            return prefix, core_basename, suffix
        end
    end
    return "", basename, ""
end

local function generate_alternative_basenames(current_prefix, core_basename, current_suffix, extension)
    local alternatives = {}
    local patterns = config.alternative_patterns[current_prefix .. "/" .. current_suffix]
        or config.alternative_patterns[current_prefix .. "/"]
        or config.alternative_patterns["/" .. current_suffix]
        or config.alternative_patterns[current_suffix]
        or {}

    -- Add alternatives based on current suffix
    for _, target_pattern in ipairs(patterns) do
        target_prefix, target_suffix = get_prefix_and_suffix(target_pattern)
        local alt_basename = target_prefix .. core_basename .. target_suffix
        table.insert(alternatives, alt_basename)
    end

    -- If no specific patterns found, try common alternatives
    if #alternatives == 0 then
        if current_suffix == "" then
            -- From base file, try test variations
            table.insert(alternatives, core_basename .. "_test")
            table.insert(alternatives, core_basename .. "_spec")
            table.insert(alternatives, core_basename .. "_impl")
            table.insert(alternatives, core_basename .. "_mock")
        else
            -- From suffixed file, try base file
            table.insert(alternatives, core_basename)
        end
    end

    return alternatives
end

local function search_alternative_files(
    root_dir,
    start_dir,
    alternative_basenames,
    extension,
    current_prefix,
    core_basename,
    current_suffix
)
    local found_files = {}

    -- First, check cache for each alternative basename
    for _, alt_basename in ipairs(alternative_basenames) do
        local cache_key = get_cache_key(alt_basename, extension, root_dir)
        local cached_path = get_from_cache(cache_key)
        if cached_path then
            table.insert(found_files, cached_path)
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Second, check directory mapping cache for predicted locations
    for _, alt_basename in ipairs(alternative_basenames) do
        local alt_prefix, _, alt_suffix = get_basename_parts(alt_basename)
        local predicted_dir = get_predicted_directory(
            start_dir,
            current_prefix .. "|" .. current_suffix .. "." .. extension,
            alt_prefix .. "|" .. alt_suffix .. "." .. extension,
            root_dir
        )
        if predicted_dir then
            local found_file = search_file_in_directory(predicted_dir, alt_basename, extension)
            if found_file then
                -- Cache both the file and confirm the directory mapping
                local cache_key = get_cache_key(alt_basename, extension, root_dir)
                add_to_cache(cache_key, found_file)
                add_directory_mapping_to_cache(
                    start_dir,
                    current_prefix .. "|" .. current_suffix .. "." .. extension,
                    predicted_dir,
                    alt_prefix .. "|" .. alt_suffix .. "." .. extension,
                    root_dir
                )
                table.insert(found_files, found_file)
            end
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Third, search upward in the directory tree
    local search_dirs = {}
    local current_dir = start_dir

    while true do
        table.insert(search_dirs, current_dir)

        if current_dir == root_dir then
            break
        end

        local parent_dir = vim.fn.fnamemodify(current_dir, ":h")
        if parent_dir == current_dir then
            break
        end

        current_dir = parent_dir

        if not vim.startswith(current_dir, root_dir) then
            break
        end
    end

    -- Search in each directory going up the tree
    for _, dir in ipairs(search_dirs) do
        for _, alt_basename in ipairs(alternative_basenames) do
            local found_file = search_file_in_directory(dir, alt_basename, extension)
            if found_file then
                local cache_key = get_cache_key(alt_basename, extension, root_dir)
                add_to_cache(cache_key, found_file)

                -- Cache the directory mapping for future predictions
                local found_dir = vim.fn.fnamemodify(found_file, ":h")
                local alt_prefix, _, alt_suffix = get_basename_parts(alt_basename)
                add_directory_mapping_to_cache(
                    start_dir,
                    current_prefix .. "|" .. current_suffix .. "." .. extension,
                    found_dir,
                    alt_prefix .. "|" .. alt_suffix .. "." .. extension,
                    root_dir
                )

                table.insert(found_files, found_file)
            end
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Fourth, do a full recursive search from root
    for _, alt_basename in ipairs(alternative_basenames) do
        local pattern = "**/" .. alt_basename .. "." .. extension
        local glob_result = vim.fn.globpath(root_dir, pattern, false, true)

        for _, file_path in ipairs(glob_result) do
            if vim.fn.filereadable(file_path) == 1 then
                local cache_key = get_cache_key(alt_basename, extension, root_dir)
                add_to_cache(cache_key, file_path)

                -- Cache the directory mapping for future predictions
                local found_dir = vim.fn.fnamemodify(file_path, ":h")
                local alt_prefix, _, alt_suffix = get_basename_parts(alt_basename)
                add_directory_mapping_to_cache(
                    start_dir,
                    current_prefix .. "|" .. current_suffix .. "." .. extension,
                    found_dir,
                    alt_prefix .. "|" .. alt_suffix .. "." .. extension,
                    root_dir
                )

                table.insert(found_files, file_path)
            end
        end
    end

    return found_files
end

local function search_files_recursively_in_tree(root_dir, basename, target_extensions)
    local found_files = {}

    -- Use vim's globpath to recursively search for files
    for _, ext in ipairs(target_extensions) do
        local pattern = "**/" .. basename .. "." .. ext
        local glob_result = vim.fn.globpath(root_dir, pattern, false, true)

        for _, file_path in ipairs(glob_result) do
            if vim.fn.filereadable(file_path) == 1 then
                table.insert(found_files, file_path)
            end
        end
    end

    return found_files
end

local function search_files_recursively(root_dir, start_dir, basename, target_extensions, source_extension)
    local found_files = {}

    -- First, check cache for each target extension
    for _, ext in ipairs(target_extensions) do
        local cache_key = get_cache_key(basename, ext, root_dir)
        local cached_path = get_from_cache(cache_key)
        if cached_path then
            table.insert(found_files, cached_path)
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Second, check directory mapping cache for predicted locations
    for _, ext in ipairs(target_extensions) do
        local predicted_dir = get_predicted_directory(start_dir, source_extension, ext, root_dir)
        if predicted_dir then
            local found_file = search_file_in_directory(predicted_dir, basename, ext)
            if found_file then
                -- Cache both the file and confirm the directory mapping
                local cache_key = get_cache_key(basename, ext, root_dir)
                add_to_cache(cache_key, found_file)
                add_directory_mapping_to_cache(start_dir, source_extension, predicted_dir, ext, root_dir)
                table.insert(found_files, found_file)
            end
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Third, search upward in the directory tree (original behavior)
    local search_dirs = {}
    local current_dir = start_dir

    while true do
        table.insert(search_dirs, current_dir)

        -- Stop if we've reached the root directory
        if current_dir == root_dir then
            break
        end

        -- Move up one directory
        local parent_dir = vim.fn.fnamemodify(current_dir, ":h")
        if parent_dir == current_dir then
            -- Reached filesystem root
            break
        end

        current_dir = parent_dir

        -- Safety check to not go above root
        if not vim.startswith(current_dir, root_dir) then
            break
        end
    end

    -- Search in each directory going up the tree
    for _, dir in ipairs(search_dirs) do
        for _, ext in ipairs(target_extensions) do
            local found_file = search_file_in_directory(dir, basename, ext)
            if found_file then
                -- Cache the result
                local cache_key = get_cache_key(basename, ext, root_dir)
                add_to_cache(cache_key, found_file)

                -- Cache the directory mapping for future predictions
                local found_dir = vim.fn.fnamemodify(found_file, ":h")
                add_directory_mapping_to_cache(start_dir, source_extension, found_dir, ext, root_dir)

                table.insert(found_files, found_file)
            end
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Fourth, if nothing found in upward search, do a full recursive search from root
    local recursive_files = search_files_recursively_in_tree(root_dir, basename, target_extensions)
    for _, found_file in ipairs(recursive_files) do
        -- Cache the result
        local file_ext = vim.fn.fnamemodify(found_file, ":e")
        local cache_key = get_cache_key(basename, file_ext, root_dir)
        add_to_cache(cache_key, found_file)

        -- Cache the directory mapping for future predictions
        local found_dir = vim.fn.fnamemodify(found_file, ":h")
        add_directory_mapping_to_cache(start_dir, source_extension, found_dir, file_ext, root_dir)

        table.insert(found_files, found_file)
    end

    return found_files
end

---------------------------------
-- Functions that map to commands
--
function M.switch_file()
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
        vim.notify("No file currently open", vim.log.levels.WARN)
        return
    end

    local basename, extension, directory = get_file_parts(current_file)

    if extension == "" then
        vim.notify("Current file has no extension", vim.log.levels.WARN)
        return
    end

    -- Get target extensions for current file extension
    local target_extensions = config.extension_maps[extension]
    if not target_extensions or #target_extensions == 0 then
        vim.notify("No extension mappings found for ." .. extension, vim.log.levels.WARN)
        return
    end

    -- Find root directory
    local root_dir = find_root_directory(directory)

    -- Search for files
    local found_files = search_files_recursively(root_dir, directory, basename, target_extensions, extension)

    if #found_files == 0 then
        local ext_list = table.concat(target_extensions, ", ")
        vim.notify(
            "No files found with basename '" .. basename .. "' and extensions: " .. ext_list,
            vim.log.levels.INFO
        )
        return
    end

    -- Open the first found file
    local target_file = found_files[1]
    vim.cmd("edit " .. vim.fn.fnameescape(target_file))

    -- Show notification with what was found
    if #found_files > 1 then
        vim.notify(
            "Switched to "
                .. vim.fn.fnamemodify(target_file, ":.")
                .. " ("
                .. (#found_files - 1)
                .. " other options available)",
            vim.log.levels.INFO
        )
    else
        vim.notify("Switched to " .. vim.fn.fnamemodify(target_file, ":."), vim.log.levels.INFO)
    end
end

function M.show_available_files()
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
        vim.notify("No file currently open", vim.log.levels.WARN)
        return
    end

    local basename, extension, directory = get_file_parts(current_file)

    if extension == "" then
        vim.notify("Current file has no extension", vim.log.levels.WARN)
        return
    end

    local target_extensions = config.extension_maps[extension]
    if not target_extensions or #target_extensions == 0 then
        vim.notify("No extension mappings found for ." .. extension, vim.log.levels.WARN)
        return
    end

    local root_dir = find_root_directory(directory)
    local found_files = search_files_recursively(root_dir, directory, basename, target_extensions, extension)

    if #found_files == 0 then
        local ext_list = table.concat(target_extensions, ", ")
        vim.notify(
            "No files found with basename '" .. basename .. "' and extensions: " .. ext_list,
            vim.log.levels.INFO
        )
        return
    end

    -- Display found files
    print("Available files for '" .. basename .. "':")
    for i, file in ipairs(found_files) do
        print(string.format("  %d. %s", i, vim.fn.fnamemodify(file, ":.")))
    end
end

function M.switch_file_alternative()
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
        vim.notify("No file currently open", vim.log.levels.WARN)
        return
    end

    local basename, extension, directory = get_file_parts(current_file)

    if extension == "" then
        vim.notify("Current file has no extension", vim.log.levels.WARN)
        return
    end

    -- Extract core basename and current suffix
    local current_prefix, core_basename, current_suffix = get_basename_parts(basename)

    -- Generate alternative basenames
    local alternative_basenames =
        generate_alternative_basenames(current_prefix, core_basename, current_suffix, extension)

    if #alternative_basenames == 0 then
        vim.notify("No alternative patterns found for '" .. basename .. "'", vim.log.levels.WARN)
        return
    end

    -- Find root directory
    local root_dir = find_root_directory(directory)

    -- Search for alternative files
    local found_files = search_alternative_files(
        root_dir,
        directory,
        alternative_basenames,
        extension,
        current_prefix,
        core_basename,
        current_suffix
    )

    if #found_files == 0 then
        local alt_list = table.concat(alternative_basenames, ", ")
        vim.notify("No alternative files found for basenames: " .. alt_list .. "." .. extension, vim.log.levels.INFO)
        return
    end

    -- Open the first found file
    local target_file = found_files[1]
    vim.cmd("edit " .. vim.fn.fnameescape(target_file))

    -- Show notification with what was found
    if #found_files > 1 then
        vim.notify(
            "Switched to "
                .. vim.fn.fnamemodify(target_file, ":.")
                .. " ("
                .. (#found_files - 1)
                .. " other alternatives available)",
            vim.log.levels.INFO
        )
    else
        vim.notify("Switched to " .. vim.fn.fnamemodify(target_file, ":."), vim.log.levels.INFO)
    end
end

function M.show_alternative_files()
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
        vim.notify("No file currently open", vim.log.levels.WARN)
        return
    end

    local basename, extension, directory = get_file_parts(current_file)

    if extension == "" then
        vim.notify("Current file has no extension", vim.log.levels.WARN)
        return
    end

    local current_prefix, core_basename, current_suffix = get_basename_parts(basename)
    local alternative_basenames =
        generate_alternative_basenames(current_prefix, core_basename, current_suffix, extension)

    if #alternative_basenames == 0 then
        vim.notify("No alternative patterns found for '" .. basename .. "'", vim.log.levels.WARN)
        return
    end

    local root_dir = find_root_directory(directory)
    local found_files = search_alternative_files(
        root_dir,
        directory,
        alternative_basenames,
        extension,
        current_prefix,
        core_basename,
        current_suffix
    )

    if #found_files == 0 then
        local alt_list = table.concat(alternative_basenames, ", ")
        vim.notify("No alternative files found for basenames: " .. alt_list .. "." .. extension, vim.log.levels.INFO)
        return
    end

    -- Display found files
    print("Alternative files for '" .. core_basename .. "' (current: " .. basename .. "  ." .. extension .. "):")
    for i, file in ipairs(found_files) do
        print(string.format("  %d. %s", i, vim.fn.fnamemodify(file, ":.")))
    end
end

function M.clear_cache()
    file_cache = {}
    cache_order = {}
    directory_mapping_cache = {}
    dir_cache_order = {}
    vim.notify("File cache and directory mappings cleared", vim.log.levels.INFO)
end

function M.show_cache_stats()
    local cache_count = #cache_order
    local dir_cache_count = #dir_cache_order
    local max_size = config.cache_size

    print(string.format("File Cache: %d/%d entries", cache_count, max_size))
    print(string.format("Directory Mapping Cache: %d/%d entries", dir_cache_count, max_size))

    if cache_count > 0 then
        print("Recent file cache entries:")
        for i = 1, math.min(3, cache_count) do
            local key = cache_order[i]
            local file = file_cache[key]
            print(string.format("  %s -> %s", key, vim.fn.fnamemodify(file, ":.")))
        end
    end

    if dir_cache_count > 0 then
        print("Recent directory mappings:")
        for i = 1, math.min(3, dir_cache_count) do
            local key = dir_cache_order[i]
            local dir = directory_mapping_cache[key]
            print(string.format("  %s -> %s", key, dir))
        end
    end
end

-------------------------------------
-- Setup command to function mappings
--
function M.setup(user_config)
    config = vim.tbl_deep_extend("force", default_config, user_config or {})

    vim.api.nvim_create_user_command("FileBlinkSwitch", M.switch_file, {
        desc = "Switch to related file based on extension mapping (e.g. foo.h <-> foo.cc)",
    })

    vim.api.nvim_create_user_command("FileBlinkSwitchAlternative", M.switch_file_alternative, {
        desc = "Switch to alternative file based on basename patterns (e.g. foo.cc <-> foo_test.cc)",
    })

    vim.api.nvim_create_user_command("FileBlinkShowFiles", M.show_available_files, {
        desc = "Show all available files for current basename",
    })

    vim.api.nvim_create_user_command("FileBlinkShowFilesAlternative", M.show_alternative_files, {
        desc = "Show all available alternative files for current basename",
    })

    vim.api.nvim_create_user_command("FileBlinkClearCache", M.clear_cache, {
        desc = "Clear the file switcher cache",
    })

    vim.api.nvim_create_user_command("FileBlinkShowStats", M.show_cache_stats, {
        desc = "Show file cache statistics",
    })
end

return M
