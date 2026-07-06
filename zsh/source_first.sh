# Create a helper function to source the first readable file from a list of files
source_first() {
	local f
	for f in "$@"; do
    	    [[ -r "$f" ]] || continue
    	    source "$f"
    	    return 0
  	done
	return 1 # return quietly
}

