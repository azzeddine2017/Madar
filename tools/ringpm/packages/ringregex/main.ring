# The Main File

func main

	? " Available Functions

| Function --> Description |

| regex_new(pattern, flags = 0) --> Create a new pattern with optional flags |
| regex_match(pattern, text) --> Test if pattern matches anywhere in text |
| regex_match_positions(pattern, text) --> Get positions of all matches (1-based) |
| regex_match_all(pattern, text)--> Get all matching strings |
| regex_find_all(pattern, text) --> Get all matches with capturing groups |
| regex_replace(pattern, text, replacement) --> Replace all matches with string |
| regex_replace_with_refs(pattern, text, replacement, options) --> Replace with backreference support |
| regex_split(pattern, text) --> Split text using pattern as delimiter |
| regex_pattern_info(pattern) --> Get pattern information |
| regex_get_error(pattern) --> Get error message for invalid pattern |
| regex_is_valid(pattern) --> Checks if the pattern is valid |

	"
	