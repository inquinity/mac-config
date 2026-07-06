# Alias $cmd to the first usable candidate. Each candidate is either a file
# path (aliased if it exists) or a command line whose first word resolves on $PATH.
alias_first() {
	local cmd="$1"
	shift || return 1

	local f candidate first
	for f in "$@"; do
	    # Try as a file path (with tilde expansion).
	    candidate=${~:-$f}
	    if [[ -f "$candidate" ]]; then
		alias "$cmd=${(q)candidate}"
		return 0
	    fi
	    # Try as a command line: first word must be in $PATH.
	    first=${f%% *}
	    if (( $+commands[$first] )); then
		alias "$cmd=${(q)f}"
		return 0
	    fi
	done
	return 1
}

# Create a helper function to alias a command to the first existing file from a list of files
#alias_first() {
#	local cmd="$1"
#	shift || return 1
#
#	local f candidate
#	for f in "$@"; do
#		candidate=${~:-$f}
#		[[ -f "$candidate" ]] || continue
#		alias "$cmd=${(q)candidate}"
#		return 0
#	done
#	return 1 # return quiety
#}

