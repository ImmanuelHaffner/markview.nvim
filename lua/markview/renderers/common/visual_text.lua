-- Applies text transformation based on the **filetype**.
--
-- Uses for getting the output text of filetypes that contain
-- special syntaxes(e.g. JSON, markdown).
local visual = {};
local lpeg = vim.lpeg;

---@param match string
---@return string
visual.md_delims_star = function (match)
	---|fS

	local inner = string.gsub(match, "^%*+", ""):gsub("%*+$", "") or "";

	if string.match(inner, "[_~`]") then
		return visual.markdown(inner);
	else
		return inner;
	end

	---|fE
end

---@param match string
---@return string
visual.md_delims_underscore = function (match)
	---|fS

	local inner = string.gsub(match, "^_+", ""):gsub("_+$", "") or "";

	if string.match(inner, "[%*~`]") then
		return visual.markdown(inner);
	else
		return inner;
	end

	---|fE
end

---@param match string
---@return string
visual.md_delims_tilde = function (match)
	---|fS

	local inner = string.gsub(match, "^~+", ""):gsub("~+$", "") or "";

	if string.match(inner, "[%*`]") then
		return visual.markdown(inner);
	else
		return inner;
	end

	---|fE
end

---@param match string
---@return string
visual.md_delims_backtick = function (match)
	local inner = string.gsub(match, "^`+", ""):gsub("`+$", "") or "";
	return inner;
end

---@param match string
---@return string
visual.md_escaped = function (match)
	local char = string.match(match, "\\(.+)$");
	return char;
end

---@param match string
---@return string
visual.md_labeled_link = function (match)
	---|fS

	local label = string.gsub(match, "^%!?%[", ""):gsub("%].-$", "");

	if string.match(label, "[%*_~`]") then
		return visual.markdown(label);
	else
		return label;
	end

	---|fE
end

---@param match string
---@return string
visual.md_autolink = function (match)
	---|fS

	local label = string.gsub(match, "^%[", ""):gsub("%]$", "");

	if string.match(label, "[%*_~`]") then
		return visual.markdown(label);
	else
		return label;
	end

	---|fE
end

---|fS "feat: LPeg parser for inline Markdown"

local _star = lpeg.P("*")^1;
local delim_star_content = lpeg.P("\\*") + ( 1 - _star );
local delim_star = lpeg.C( _star * delim_star_content^1 * _star ) / visual.md_delims_star;

local _underscore = lpeg.P("_")^1;
local delim_underscore_content = lpeg.P("\\_") + ( 1 - _underscore );
local delim_underscore = lpeg.C( _underscore * delim_underscore_content^1 * _underscore ) / visual.md_delims_underscore;

local _tilde = lpeg.P("~")^1;
local delim_tilde_content = lpeg.P("\\~") + ( 1 - _tilde );
local delim_tilde = lpeg.C( _tilde * delim_tilde_content^1 * _tilde ) / visual.md_delims_tilde;

local _backtick = lpeg.P("`")^1;
local delim_backtick_content = lpeg.P("\\`") + ( 1 - _backtick );
local delim_backtick = lpeg.C( _backtick * delim_backtick_content^1 * _backtick ) / visual.md_delims_backtick;

local escaped = lpeg.C( lpeg.P("\\") * lpeg.P(1) ) / visual.md_escaped;

local image_label_char = lpeg.P("\\]") + ( 1 - lpeg.P("]") );
local image_link_char = lpeg.P("\\)") + ( 1 - lpeg.P(")") );
local image = lpeg.C( lpeg.P("![") * image_label_char^0 * lpeg.P("](") * image_link_char^0 * lpeg.P(")") ) / visual.md_labeled_link;

local link_label_char = lpeg.P("\\]") + ( 1 - lpeg.P("]") );
local link_link_char = lpeg.P("\\)") + ( 1 - lpeg.P(")") );
local link = lpeg.C( lpeg.P("[") * link_label_char^0 * lpeg.P("](") * link_link_char^0 * lpeg.P(")") ) / visual.md_labeled_link;
local autolink = lpeg.C( lpeg.P("[") * link_label_char^0 * lpeg.P("]") ) / visual.md_autolink;

local any = lpeg.P(1);
local token = escaped + delim_backtick + delim_star + delim_underscore + delim_tilde + image + link + autolink + any;

local inline = lpeg.Cs(token^0);

---|fE

---@param str string
---@return string
visual.markdown = function (str)
	---|fS

	return inline:match(str);

	---|fE
end

--------------------------------------------------------------------------------

---@param match string
---@return string
visual.json_string = function (match)
	local inner = string.gsub(match, '^"', ""):gsub('"$', "") or "";

	if string.match(inner, '"') then
		return visual.json(inner);
	else
		return inner;
	end
end

---@param match string
---@return string
visual.json_escaped = function (match)
	local char = string.match(match, "\\(.+)$");
	return char;
end

---|fS "feat: LPeg parser for inline JSON"

local _quote = lpeg.P('"')^1;
local jstring_content = lpeg.P('\\"') + ( 1 - _quote );
local jstring = lpeg.C( _quote * jstring_content^1 * _quote ) / visual.json_string;

local jescaped = lpeg.C( lpeg.P("\\") * lpeg.P(1) ) / visual.json_escaped;

local jtoken = jescaped + jstring + any;

local jinline = lpeg.Cs(jtoken^0);

---|fE

---@param str string
---@return string
visual.json = function (str)
	---|fS

	return jinline:match(str);

	---|fE
end

--------------------------------------------------------------------------------

--- Cache for the `language -> ft` resolution.
---
--- `get_visual_text()` is called once per line of every code block on every
--- render, but the mapping from a fenced-code `language` to a filetype (and
--- whether a usable transform exists for it) is invariant. Detecting it with
--- `vim.filetype.match()` on each call re-runs the entire filetype pattern
--- engine hundreds of times per render for a handful of distinct languages
--- (including the common no-language case). Memoize it instead.
---
--- Keyed by the raw `language` argument; a sentinel stands in for `nil` so the
--- no-language case is resolved once and reused. Each entry stores the
--- resolved `ft` and the transform function to apply (or `false` when no
--- usable transform exists, so the line is returned verbatim).
---@type table<string, { ft: string?, transform: (fun(line: string): string)|false }>
visual.ft_cache = {};

--- Sentinel key for a `nil` language.
local NIL_LANGUAGE = "\0nil";

---@param language string?
---@return { ft: string?, transform: (fun(line: string): string)|false }
visual.resolve_ft = function (language)
	---|fS

	local key = language == nil and NIL_LANGUAGE or language;

	local cached = visual.ft_cache[key];
	if cached ~= nil then
		return cached;
	end

	local ft = vim.filetype.match({
		filename = string.format("example.%s", language)
	}) or language;

	local entry;

	local found_parser = pcall(vim.treesitter.language.inspect, ft);

	if not found_parser or ft == nil or type(visual[ft]) ~= "function" then
		entry = { ft = ft, transform = false };
	else
		entry = { ft = ft, transform = visual[ft] };
	end

	visual.ft_cache[key] = entry;
	return entry;

	---|fE
end

---@param language string?
---@param line string
---@return string
visual.get_visual_text = function (language, line)
	---|fS

	local entry = visual.resolve_ft(language);

	if entry.transform == false then
		return line;
	end

	local could_get, visual_text = pcall(entry.transform, line);
	return could_get and visual_text or line;

	---|fE
end

return visual;
